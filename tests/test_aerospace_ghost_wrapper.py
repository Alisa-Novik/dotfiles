"""Exercise the wrapper with a fake scanner; never access the live desktop."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "stow/macos-personal/.local/bin/aerospace-clear-stale-snapshots"
MOCK = r'''
import json, os, pathlib, sys
with pathlib.Path(os.environ['MOCK_CALLS']).open('a') as calls:
    calls.write(json.dumps(sys.argv[1:]) + '\n')
if '--guard' in sys.argv:
    pathlib.Path(os.environ['MOCK_REPAIR']).touch()
print(os.environ.get('MOCK_RESULT', 'mock scanner result'))
if os.environ.get('MOCK_FAILURE'):
    print('mock scanner error', file=sys.stderr)
    sys.exit(int(os.environ['MOCK_FAILURE']))
'''


@unittest.skipUnless(Path('/usr/bin/lockf').exists(), 'requires macOS lockf')
class GhostWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='aerospace-ghost-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.cache = self.home / 'Library/Caches/aerospace-ghost-guard'
        self.cache.mkdir(parents=True)
        self.wrapper = self.root / SCRIPT.name
        shutil.copyfile(SCRIPT, self.wrapper)
        source = self.root / '.aerospace-snapshot-scan.swift'
        source.write_text('#error("Tests must never compile a live scanner")\n')
        self.scanner = self.cache / 'scan-onscreen-snapshots'
        self.scanner.write_text('#!' + sys.executable + '\n' + MOCK)
        self.scanner.chmod(0o700)
        old = time.time() - 30
        os.utime(source, (old, old))
        self.calls_path = self.root / 'calls.jsonl'
        self.repair = self.root / 'repair'
        self.log = self.home / '.local/state/aerospace-fullscreen.log'
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.root),
                        MOCK_CALLS=str(self.calls_path), MOCK_REPAIR=str(self.repair))
        self.env.pop('MOCK_FAILURE', None)
        self.env.pop('MOCK_RESULT', None)

    def run_wrapper(self, *args, **env):
        return subprocess.run(['/bin/bash', str(self.wrapper), *args],
                              env={**self.env, **env}, capture_output=True,
                              text=True, timeout=20)

    def calls(self):
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()] if self.calls_path.exists() else []

    def assert_dispatched(self, mode):
        calls = self.calls()
        self.assertTrue(calls, 'mock scanner was never called')
        self.assertTrue(all(call == [mode] for call in calls), calls)

    def test_dry_run_dispatches_only_read_only_mode(self):
        before = self.scanner.read_bytes()
        result = self.run_wrapper('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_dispatched('--dry-run')
        self.assertIn('mock scanner result', result.stdout)
        self.assertFalse(self.repair.exists())
        self.assertFalse(self.log.exists())
        self.assertEqual(self.scanner.read_bytes(), before)

    def test_background_dispatches_guard_and_logs_result(self):
        result = self.run_wrapper('--background')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_dispatched('--guard')
        self.assertIn('mock scanner result', self.log.read_text())

    def test_delayed_snapshot_is_checked_even_if_first_sample_is_empty(self):
        result = self.run_wrapper('--background', MOCK_RESULT='{"status":"skipped","candidates":[]}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [['--guard'], ['--guard']])

    def test_background_preserves_failure_status_and_diagnostic(self):
        result = self.run_wrapper('--background', MOCK_FAILURE='7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assert_dispatched('--guard')
        self.assertIn('mock scanner error', self.log.read_text())

    def test_failure_cooldown_skips_background_but_allows_manual_dry_run(self):
        failed = self.run_wrapper('--background', MOCK_FAILURE='7')
        self.assertEqual(failed.returncode, 7)
        self.assertTrue((self.cache / 'recovery-failed').exists())
        calls, log = self.calls(), self.log.read_text()
        skipped = self.run_wrapper('--background')
        self.assertEqual(skipped.returncode, 0, skipped.stderr)
        self.assertEqual(self.calls(), calls)
        self.assertEqual(self.log.read_text(), log)
        manual = self.run_wrapper('--dry-run')
        self.assertEqual(manual.returncode, 0, manual.stderr)
        self.assertEqual(self.calls(), calls + [['--dry-run']])
        self.assertIn('mock scanner result', manual.stdout)

    def test_repeated_state_changes_get_only_two_samples(self):
        result = self.run_wrapper('--background', MOCK_RESULT='{"status":"state-changed"}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [['--guard'], ['--guard']])
        self.assertEqual(self.log.read_text().count('"status":"state-changed"'), 2)
        self.assertFalse((self.cache / 'recovery-failed').exists())

    def test_stale_unlocked_file_does_not_block_recovery(self):
        lock = self.cache / 'recovery.lock'
        lock.write_text('99999999\n')
        inode = lock.stat().st_ino
        result = self.run_wrapper('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_dispatched('--dry-run')
        self.assertEqual(lock.stat().st_ino, inode)

    def test_live_kernel_lock_excludes_another_scanner(self):
        with (self.cache / 'recovery.lock').open('w') as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_wrapper('--background')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.calls(), [])
            self.assertFalse(self.log.exists())
        result = self.run_wrapper('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_dispatched('--dry-run')

    def test_invalid_arguments_never_dispatch_scanner(self):
        for args in [('--bogus',), ('--dry-run', 'extra'),
                     ('--background', '--locked', 'extra')]:
            with self.subTest(args=args):
                result = self.run_wrapper(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
