"""Check empty-desktop guards with fake CLI/open commands; never activate apps."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "stow/macos-personal/.local/bin/aerospace-empty-desktop"


class EmptyDesktopWrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aerospace-empty-desktop-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.calls = self.root / "calls.jsonl"
        self.mock = self.root / "mock-command"
        self.mock.write_text("""#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CALLS'], 'a') as out:
    out.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'list-workspaces':
    print(os.environ.get('EMPTY_WORKSPACE', ''))
    sys.exit(int(os.environ.get('QUERY_STATUS', '0')))
""")
        self.mock.chmod(0o700)
        self.script = self.root / "aerospace-empty-desktop"
        self.script.write_text(SOURCE.read_text()
                               .replace("/opt/homebrew/bin/aerospace", str(self.mock))
                               .replace("/usr/bin/open", str(self.mock)))
        # A prepared bundle prevents compilation. This mock app cannot run.
        self.app = self.root / "Library/Caches/aerospace-empty-desktop/AeroSpace Empty Desktop.app"
        binary = self.app / "Contents/MacOS/aerospace-empty-desktop"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/sh\nexit 99\n")
        binary.chmod(0o700)
        self.env = {**os.environ, "HOME": str(self.root), "CALLS": str(self.calls)}

    def run_script(self, *args, **env):
        result = subprocess.run(["/bin/bash", str(self.script), *args],
                                env={**self.env, **env}, capture_output=True,
                                text=True, timeout=3)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        return result, calls

    def test_occupied_workspace_never_launches_an_app(self):
        result, calls = self.run_script("6", EMPTY_WORKSPACE="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)

    def test_later_navigation_cancels_request(self):
        result, calls = self.run_script("6", EMPTY_WORKSPACE="7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)

    def test_query_failure_never_launches_an_app(self):
        result, calls = self.run_script("6", QUERY_STATUS="7")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(calls), 1)

    def test_current_empty_workspace_only_background_launches_guarded_url(self):
        result, calls = self.run_script("6", EMPTY_WORKSPACE="6")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1], ["-g", "-a", str(self.app),
                                    "aerospace-empty-desktop://workspace/6"])

    def test_non_workspace_focus_and_invalid_input_do_nothing(self):
        for args in [(), ("",), ("--prepare",), ("6; touch unwanted",), ("6", "extra")]:
            with self.subTest(args=args):
                _, calls = self.run_script(*args)
                self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
