"""Test ghost eligibility on fixtures, without hiding apps or reading the desktop."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'stow/macos-personal/.local/bin/.aerospace-snapshot-scan.swift'
HARNESS = r'''
struct PolicyFixture: Decodable {
    let candidate: SnapshotCandidate
    let snapshot: GuardSnapshot
    let comparedSnapshot: GuardSnapshot?
}
do {
    let fixture = try JSONDecoder().decode(PolicyFixture.self, from: FileHandle.standardInput.readDataToEndOfFile())
    if let compared = fixture.comparedSnapshot {
        print(stableContext(fixture.snapshot, compared) ? "stable" : "changed")
    } else {
        print(eligibility(candidate: fixture.candidate, in: fixture.snapshot) == nil ? "eligible" : "protected")
    }
} catch {
    fputs("fixture failed: \(error)\n", stderr)
    exit(1)
}
'''
CANDIDATE = {'pid': 9541, 'owner': 'Discord', 'windowID': 83723}
EVIDENCE = {
    'pid': 9541, 'windowID': 83723, 'role': 'AXWindow', 'subrole': 'AXUnknown',
    'title': '', 'childCount': 0, 'focused': False, 'main': False,
    'fullscreen': False, 'minimized': False, 'closeButtonAbsent': True,
    'positionSettable': True, 'sizeSettable': False,
    'minimizedSettable': False, 'fullscreenSettable': False,
}
BASE = {
    'candidates': [CANDIDATE],
    'axEvidence': [EVIDENCE],
    'managedWindows': [
        {'windowID': 77171, 'pid': 9541, 'workspace': '4'},
        {'windowID': 83626, 'pid': 61581, 'workspace': '1'},
    ],
    'visibleWorkspaces': ['1'], 'frontmostPID': 61581, 'hiddenPIDs': [],
    'nativeDisplays': [{
        'identifier': 'display-1', 'currentSpaceID': 3,
        'spaces': [
            {'id': 3, 'type': 0, 'fullscreenWindowID': None, 'windows': []},
            {'id': 7089, 'type': 4, 'fullscreenWindowID': 77171,
             'windows': [{'windowID': 77171, 'pid': 9541}]},
        ],
    }],
}


@unittest.skipUnless(sys.platform == 'darwin', 'requires macOS Swift frameworks')
class GhostPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='ghost-policy-')
        cls.addClassCleanup(cls.temp.cleanup)
        root = Path(cls.temp.name)
        source = SOURCE.read_text()
        prefix, marker, trailing = source.rpartition('\nsnapshotScannerMain()')
        if not marker or trailing.strip():
            raise AssertionError('Expected isolated scanner main entry point')
        fixture_source = root / 'policy.swift'
        fixture_source.write_text(prefix + '\n' + HARNESS)
        cls.binary = root / 'policy'
        result = subprocess.run(['/usr/bin/swiftc', str(fixture_source), '-o', str(cls.binary)],
                                capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise AssertionError(result.stderr)

    def decision(self, snapshot, candidate=CANDIDATE, compared=None):
        fixture = {'candidate': candidate, 'snapshot': snapshot, 'comparedSnapshot': compared}
        result = subprocess.run([str(self.binary)], input=json.dumps(fixture),
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_observed_orphan_with_inactive_native_parent_is_eligible(self):
        self.assertEqual(self.decision(BASE), 'eligible')

    def test_managed_window_is_protected_even_if_it_looks_like_snapshot(self):
        state = copy.deepcopy(BASE)
        state['managedWindows'].append({'windowID': 83723, 'pid': 9541, 'workspace': '4'})
        self.assertEqual(self.decision(state), 'protected')

    def test_proven_snapshot_can_be_moved_when_owner_is_on_visible_monitor(self):
        state = copy.deepcopy(BASE)
        state['visibleWorkspaces'].append('4')
        self.assertEqual(self.decision(state), 'eligible')

    def test_proven_snapshot_can_be_moved_without_hiding_frontmost_app(self):
        state = copy.deepcopy(BASE)
        state['frontmostPID'] = 9541
        self.assertEqual(self.decision(state), 'eligible')

    def test_hidden_app_is_not_unhidden(self):
        state = copy.deepcopy(BASE)
        state['hiddenPIDs'] = [9541]
        self.assertEqual(self.decision(state), 'protected')

    def test_visible_native_fullscreen_on_any_monitor_is_protected(self):
        state = copy.deepcopy(BASE)
        second = copy.deepcopy(state['nativeDisplays'][0])
        second.update(identifier='display-2', currentSpaceID=7089)
        state['nativeDisplays'].append(second)
        self.assertEqual(self.decision(state), 'protected')

    def test_unknown_native_space_state_fails_closed(self):
        for change in ('empty', 'missing-current', 'unknown-type'):
            state = copy.deepcopy(BASE)
            if change == 'empty': state['nativeDisplays'] = []
            elif change == 'missing-current': state['nativeDisplays'][0]['currentSpaceID'] = 99
            else: state['nativeDisplays'][0]['spaces'][0]['type'] = 99
            with self.subTest(change=change):
                self.assertEqual(self.decision(state), 'protected')

    def test_snapshot_after_native_parent_was_closed_is_eligible(self):
        state = copy.deepcopy(BASE)
        state['nativeDisplays'][0]['spaces'].pop()
        self.assertEqual(self.decision(state), 'eligible')

    def test_geometry_without_ax_evidence_is_protected(self):
        state = copy.deepcopy(BASE)
        state['axEvidence'] = []
        self.assertEqual(self.decision(state), 'protected')

    def test_real_or_interactive_windows_are_protected(self):
        for key, value in {
            'subrole': 'AXStandardWindow', 'role': 'AXDialog', 'title': 'Call',
            'childCount': 1, 'focused': True, 'main': True, 'fullscreen': True,
            'minimized': True, 'closeButtonAbsent': False, 'positionSettable': False,
            'sizeSettable': True, 'minimizedSettable': True, 'fullscreenSettable': True,
            'pid': 99999, 'windowID': 99999,
        }.items():
            state = copy.deepcopy(BASE)
            state['axEvidence'][0][key] = value
            with self.subTest(key=key):
                self.assertEqual(self.decision(state), 'protected')

    def test_window_without_managed_owner_is_protected(self):
        state = copy.deepcopy(BASE)
        state['managedWindows'] = [w for w in state['managedWindows'] if w['pid'] != 9541]
        self.assertEqual(self.decision(state), 'protected')

    def test_real_native_fullscreen_window_is_protected(self):
        state = copy.deepcopy(BASE)
        state['nativeDisplays'][0]['spaces'][1]['fullscreenWindowID'] = 83723
        self.assertEqual(self.decision(state), 'protected')

    def test_candidate_that_disappeared_is_not_repaired(self):
        state = copy.deepcopy(BASE)
        state['candidates'] = []
        self.assertEqual(self.decision(state), 'protected')

    def test_navigation_or_native_transition_invalidates_observation(self):
        self.assertEqual(self.decision(BASE, compared=BASE), 'stable')
        for change in ('focus', 'workspace', 'space', 'native-window', 'ax-signature'):
            state = copy.deepcopy(BASE)
            if change == 'focus': state['frontmostPID'] = 9541
            elif change == 'workspace': state['visibleWorkspaces'] = ['2']
            elif change == 'space': state['nativeDisplays'][0]['currentSpaceID'] = 7089
            elif change == 'native-window': state['nativeDisplays'][0]['spaces'][1]['windows'][0]['windowID'] = 99999
            else: state['axEvidence'][0]['childCount'] = 1
            with self.subTest(change=change):
                self.assertEqual(self.decision(BASE, compared=state), 'changed')


if __name__ == '__main__':
    unittest.main()
