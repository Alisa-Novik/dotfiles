import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "stow/macos-personal/.local/bin/aerospace-safe-fullscreen"


class FullscreenTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.calls = self.root / "calls.jsonl"
        self.mock = self.root / "aerospace"
        self.mock.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ['MOCK_CALLS'])
previous = p.read_text().splitlines() if p.exists() else []
with p.open('a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'list-windows':
    changed = os.environ.get('MOCK_CHANGED') and previous
    print('99' if changed else '42')
if sys.argv[1] == os.environ.get('MOCK_FAIL'):
    print('AX command rejected', file=sys.stderr)
    sys.exit(7)
""")
        self.mock.chmod(0o755)
        self.env = {**os.environ, "AEROSPACE_BIN": str(self.mock), "MOCK_CALLS": str(self.calls)}

    def run_script(self, *args, **env):
        result = subprocess.run(["/bin/bash", str(SCRIPT), *args], env={**self.env, **env}, capture_output=True, text=True, timeout=4)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        return result, calls

    def test_normal_toggle_only_uses_managed_fullscreen(self):
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, [["fullscreen", "--no-outer-gaps"]])

    def test_native_exit_is_pinned_and_schedules_no_later_mutation(self):
        result, calls = self.run_script("--exit-native")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, [
            ["list-windows", "--focused", "--format", "%{window-id}"],
            ["macos-native-fullscreen", "off", "--window-id", "42"],
        ])

    def test_native_failure_is_not_reported_as_success(self):
        result, calls = self.run_script("--exit-native", MOCK_FAIL="macos-native-fullscreen")
        self.assertEqual(result.returncode, 7)
        self.assertIn("AX command rejected", result.stderr)
        self.assertFalse(any(c[0] == "fullscreen" for c in calls))

    def test_normal_fullscreen_failure_propagates(self):
        result, _ = self.run_script(MOCK_FAIL="fullscreen")
        self.assertEqual(result.returncode, 7)

    def test_unexpected_argument_does_not_change_a_window(self):
        result, calls = self.run_script("--exit-native", "extra")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
