"""Exercise the navigation compatibility entry point without touching the desktop."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "stow/macos-personal/.local/bin/aerospace-workspace"
)


class WorkspaceNavigationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aerospace-workspace-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / "calls.jsonl"
        self.env = dict(os.environ, MOCK_CALL_LOG=str(self.log))
        self.mock = self.root / "aerospace"
        self.mock.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['MOCK_CALL_LOG'], 'a') as out:\n"
            "    out.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "print(os.environ.get('MOCK_STDERR', ''), file=sys.stderr, end='')\n"
            "sys.exit(int(os.environ.get('MOCK_EXIT_CODE', '0')))\n"
        )
        self.mock.chmod(0o700)

        # A broken helper must not be consulted, even for an empty workspace.
        # Replace all legacy endpoints in the copied script so a regression
        # cannot restart services or talk to the actual window managers.
        self.unavailable = self.root / "unavailable-helper"
        self.unavailable.write_text(
            "#!/bin/bash\n"
            "printf '\"unexpected helper call\"\\n' >> \"$MOCK_CALL_LOG\"\n"
            "exit 95\n"
        )
        self.unavailable.chmod(0o700)
        source = SOURCE.read_text()
        source = source.replace("/opt/homebrew/bin/aerospace", str(self.mock))
        for endpoint in (
            "/opt/homebrew/bin/yabai",
            "/bin/launchctl",
            "/usr/bin/shlock",
        ):
            source = source.replace(endpoint, str(self.unavailable))
        source = source.replace("/tmp/aerospace-", str(self.root / "aerospace-"))
        self.script = self.root / "aerospace-workspace"
        self.script.write_text(source)

    def run_script(self, *args, **env):
        return subprocess.run(
            ["/bin/bash", str(self.script), *args],
            env=dict(self.env, **env),
            capture_output=True,
            text=True,
            timeout=2,
        )

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_empty_workspace_uses_one_direct_command_without_helpers(self):
        result = self.run_script("10")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [["workspace", "--", "10"]])

    def test_workspace_name_is_one_literal_argument(self):
        marker = self.root / "must-not-exist"
        workspace = f"--help; touch {marker}; $(touch {marker}) `touch {marker}`"
        result = self.run_script(workspace)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [["workspace", "--", workspace]])
        self.assertFalse(marker.exists())

    def test_server_failure_is_reported_without_retrying(self):
        result = self.run_script("3", MOCK_EXIT_CODE="7", MOCK_STDERR="rejected\n")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stderr, "rejected\n")
        self.assertEqual(self.calls(), [["workspace", "--", "3"]])

    def test_invalid_arguments_do_not_call_server(self):
        for args in ((), ("",), ("1", "2")):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage:", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_missing_executable_has_a_clear_error(self):
        self.mock.unlink()
        result = self.run_script("1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("AeroSpace is not installed", result.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
