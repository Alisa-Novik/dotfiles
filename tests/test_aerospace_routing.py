"""Isolated behavior checks; no command can reach the live desktop."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BIN = Path(__file__).resolve().parents[1] / 'stow/macos-personal/.local/bin'
MOCK = r'''
import json, os, sys, time
from pathlib import Path
state = Path(os.environ['MOCK_STATE'])
calls = Path(os.environ['MOCK_CALLS'])
args = sys.argv[1:]
with calls.open('a') as f:
    f.write(json.dumps(args) + '\n')
def read(): return json.loads(state.read_text())
def save(data):
    tmp = state.with_suffix('.tmp')
    tmp.write_text(json.dumps(data))
    tmp.replace(state)
data = read()
command = args[0]
if command in data.get('fail', []):
    print('mock failure: ' + command, file=sys.stderr)
    sys.exit(7)
if command == 'subscribe':
    last = data['focused']
    print(json.dumps({'_event': 'focused-workspace-changed', 'workspace': last, 'prevWorkspace': last}), flush=True)
    while True:
        time.sleep(.01)
        current = read()['focused']
        if current != last:
            print(json.dumps({'_event': 'focused-workspace-changed', 'workspace': current, 'prevWorkspace': last}), flush=True)
            last = current
elif command == 'list-workspaces':
    print(data['focused'])
elif command == 'list-apps':
    if data.get('navigate_and_back'):
        old = data['focused']
        data['focused'] = '8'; save(data); time.sleep(.08)
        data['focused'] = old; save(data); time.sleep(.08)
    print('\n'.join(data['apps']))
elif command == 'list-windows':
    fmt = args[args.index('--format') + 1]
    for w in data['windows']:
        row = fmt.replace('%{tab}', '\t')
        for key, value in w.items():
            row = row.replace('%{' + key + '}', str(value))
        print(row)
elif command == 'workspace':
    data['focused'] = args[-1]; save(data)
'''
OPEN = r'''
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE'])
data = json.loads(p.read_text())
args = sys.argv[1:]
with Path(os.environ['MOCK_CALLS']).open('a') as f:
    f.write(json.dumps(['open'] + args) + '\n')
bundle = next(b for a, b in {
 '/Applications/Firefox.app': 'org.mozilla.firefox',
 '/Applications/kitty.app': 'net.kovidgoyal.kitty',
 '/Applications/Telegram.app': 'com.tdesktop.Telegram',
}.items() if a in args)
data['apps'].append(bundle)
data['windows'].append({'window-id': 900 + len(data['windows']), 'app-pid': 1250,
 'app-bundle-id': bundle, 'window-title': 'Main', 'workspace': data['focused']})
p.write_text(json.dumps(data))
'''


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='aerospace-routing-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        (self.home / '.local/bin').mkdir(parents=True)
        (self.home / '.local/bin/aerospace-route-window').symlink_to(BIN / 'aerospace-route-window')
        self.state = self.root / 'state.json'
        self.calls_path = self.root / 'calls'
        self.data = {'focused': '1', 'apps': ['org.mozilla.firefox', 'net.kovidgoyal.kitty', 'com.tdesktop.Telegram'],
                     'windows': [self.window()]}
        self.save()
        self.env = dict(os.environ, HOME=str(self.home), MOCK_STATE=str(self.state),
                        MOCK_CALLS=str(self.calls_path), TMPDIR=str(self.root),
                        AEROSPACE_BIN=str(self.executable('aerospace', MOCK)),
                        AEROSPACE_OPEN_BIN=str(self.executable('open', OPEN)),
                        AEROSPACE_PS_BIN=str(self.executable('ps', r'''
import os, sys
args = sys.argv[1:]
if 'lstart=' in args: print('Fri Sep 4 12:00:00 2026')
elif 'command=' in args: print(os.environ.get('MOCK_FIREFOX_COMMAND', '/Applications/Firefox.app/Contents/MacOS/firefox -P default-release'))
elif not os.environ.get('MOCK_NO_FIREFOX'): print('1250 /Applications/Firefox.app/Contents/MacOS/firefox -P default-release')
''')),
                        AEROSPACE_LSOF_BIN='/usr/bin/true', AEROSPACE_SESSION_GRACE_SECONDS='0')

    def executable(self, name, code):
        path = self.root / name
        path.write_text('#!' + sys.executable + '\n' + code)
        path.chmod(0o755)
        return path

    def window(self, bundle='net.kovidgoyal.kitty', title='Main'):
        return {'window-id': 101, 'app-pid': 1250, 'app-bundle-id': bundle,
                'window-title': title, 'workspace': '4'}

    def save(self): self.state.write_text(json.dumps(self.data))
    def calls(self):
        return [json.loads(x) for x in self.calls_path.read_text().splitlines()] if self.calls_path.exists() else []
    def mutations(self):
        return [c for c in self.calls() if not c[0].startswith('list-') and c[0] != 'subscribe']
    def run_script(self, script, *args):
        return subprocess.run(['/bin/bash', str(BIN / script), *args], env=self.env,
                              capture_output=True, text=True, timeout=15)
    def route(self, bundle='net.kovidgoyal.kitty', title='Main', *flags):
        return self.run_script('aerospace-route-window', *flags, '--', '101', '1250', bundle, title)

    def test_new_terminal_preserves_layout_and_never_focuses(self):
        result = self.route()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [['move-node-to-workspace', '--window-id', '101', '--', '2']])

    def test_nsfw_profile_only_places_window(self):
        self.env['MOCK_FIREFOX_COMMAND'] = '/Applications/Firefox.app/Contents/MacOS/firefox -P NSFW'
        result = self.route('org.mozilla.firefox')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [['move-node-to-workspace', '--window-id', '101', '--', '3']])

    def test_rediscovery_preserves_manual_placement_but_force_resets(self):
        self.assertEqual(self.route().returncode, 0)
        self.assertEqual(self.route().returncode, 0)
        self.assertEqual(len(self.mutations()), 1)
        self.assertEqual(self.route('net.kovidgoyal.kitty', 'Main', '--force').returncode, 0)
        self.assertEqual(len(self.mutations()), 2)

    def test_remember_never_mutates_desktop(self):
        self.assertEqual(self.route('net.kovidgoyal.kitty', 'Main', '--remember').returncode, 0)
        self.assertEqual(self.route().returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_unknown_telegram_title_is_left_alone(self):
        self.data['windows'] = [self.window('com.tdesktop.Telegram', '')]; self.save()
        result = self.route('com.tdesktop.Telegram', '')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [])
        self.assertFalse((self.home / '.local/state/aerospace-routing').exists())

    def test_media_viewer_floats_without_moving(self):
        self.assertEqual(self.route('com.tdesktop.Telegram', 'Media viewer').returncode, 0)
        self.assertEqual(self.mutations(), [['layout', '--window-id', '101', 'floating']])

    def test_layout_failure_surfaces_and_does_not_move_or_mark_done(self):
        self.data['fail'] = ['layout']; self.save()
        result = self.route('org.mozilla.macos.FirefoxVPN')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('mock failure: layout', result.stderr)
        self.assertEqual([c[0] for c in self.mutations()], ['layout'])
        self.assertEqual(list(self.home.glob('.local/state/aerospace-routing/*.done')), [])

    def test_move_failure_is_retryable_and_preserves_stderr(self):
        self.data['fail'] = ['move-node-to-workspace']; self.save()
        result = self.route()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('mock failure: move-node-to-workspace', result.stderr)
        self.data['fail'] = []; self.save()
        self.assertEqual(self.route().returncode, 0)
        self.assertEqual(len(self.mutations()), 2)

    def test_stale_process_lock_is_recovered(self):
        directory = self.home / '.local/state/aerospace-routing'
        directory.mkdir(parents=True)
        child = subprocess.Popen(['/usr/bin/true'])
        child.wait()
        (directory / '1250-Fri-Sep-4-12-00-00-2026-101.lock').write_text(str(child.pid) + '\n')
        self.assertEqual(self.route().returncode, 0)
        self.assertEqual(len(self.mutations()), 1)

    def test_numeric_id_validation(self):
        result = self.run_script('aerospace-route-window', '--', '../bad', '1250', 'net.kovidgoyal.kitty')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.mutations(), [])

    def test_default_align_is_local_and_preserves_tree(self):
        result = self.run_script('aerospace-align-windows', '--no-notify')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [['balance-sizes', '--workspace', '1']])

    def test_default_align_failure_is_nonzero(self):
        self.data['fail'] = ['balance-sizes']; self.save()
        result = self.run_script('aerospace-align-windows', '--no-notify')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('mock failure: balance-sizes', result.stderr)

    def test_global_reset_reports_partial_failures(self):
        self.data['fail'] = ['move-node-to-workspace', 'layout', 'balance-sizes', 'flatten-workspace-tree']; self.save()
        result = self.run_script('aerospace-align-windows', '--reset-all', '--no-notify')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('16 operation(s) failed', result.stderr)
        self.assertIn('mock failure:', result.stderr)
        self.assertEqual(len(self.mutations()), 16)

    def test_dry_runs_do_not_mutate_desktop_or_write_state(self):
        for script, args in [('aerospace-route-window', ('--dry-run', '--', '101', '1250', 'net.kovidgoyal.kitty', 'Main')),
                             ('aerospace-align-windows', ('--dry-run', '--reset-all')),
                             ('aerospace-session-start', ('--dry-run',))]:
            result = self.run_script(script, *args)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [])
        self.assertFalse((self.home / '.local/state').exists())

    def test_startup_preserves_existing_windows_and_focus(self):
        result = self.run_script('aerospace-session-start', '--no-wait')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [])
        self.assertEqual(self.route().returncode, 0)
        self.assertEqual(self.mutations(), [])

    def test_startup_does_not_steal_focus_after_navigation_and_back(self):
        self.data['navigate_and_back'] = True; self.save()
        result = self.run_script('aerospace-session-start', '--no-wait')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mutations(), [])

    def test_startup_routes_only_newly_launched_apps(self):
        self.data['apps'].remove('com.tdesktop.Telegram'); self.save()
        result = self.run_script('aerospace-session-start', '--no-wait')
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = self.mutations()
        self.assertEqual([c[0] for c in mutations], ['open', 'move-node-to-workspace'])
        self.assertEqual(mutations[1][-1], '5')
        self.assertNotIn('101', mutations[1])


if __name__ == '__main__': unittest.main()
