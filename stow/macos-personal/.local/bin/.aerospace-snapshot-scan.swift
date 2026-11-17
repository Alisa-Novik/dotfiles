import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

// Default mode retains the old read-only TSV scan. --inspect/--dry-run explain
// eligibility; only --guard moves a proven snapshot outside the displays.
// The caller owns scheduling and locking. Never hide or activate the owner app.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct SnapshotAXEvidence: Codable, Equatable {
    let windowID: UInt32
    let pid: Int32
    let role: String
    let subrole: String
    let title: String
    let childCount: Int
    let focused: Bool
    let main: Bool
    let fullscreen: Bool
    let minimized: Bool
    let closeButtonAbsent: Bool
    let positionSettable: Bool
    let sizeSettable: Bool
    let minimizedSettable: Bool
    let fullscreenSettable: Bool

    var isSnapshot: Bool {
        role == "AXWindow" && subrole == "AXUnknown" && title.isEmpty
            && childCount == 0 && !focused && !main && !fullscreen && !minimized
            && closeButtonAbsent && positionSettable && !sizeSettable
            && !minimizedSettable && !fullscreenSettable
    }
}
struct SnapshotCandidate: Codable, Equatable {
    let pid: Int32
    let owner: String
    let windowID: UInt32
}
struct ManagedWindow: Codable, Equatable {
    let windowID: UInt32
    let pid: Int32
    let workspace: String
}
struct NativeFullscreenWindow: Codable, Equatable {
    let windowID: UInt32
    let pid: Int32
}
struct NativeSpace: Codable, Equatable {
    let id: UInt64
    let type: Int
    let fullscreenWindowID: UInt32?
    let windows: [NativeFullscreenWindow]
}
struct NativeDisplay: Codable, Equatable {
    let identifier: String
    let currentSpaceID: UInt64
    let spaces: [NativeSpace]
}
struct GuardSnapshot: Codable, Equatable {
    let candidates: [SnapshotCandidate]
    let axEvidence: [SnapshotAXEvidence]
    let managedWindows: [ManagedWindow]
    let visibleWorkspaces: [String]
    let frontmostPID: Int32
    let hiddenPIDs: [Int32]
    let nativeDisplays: [NativeDisplay]
}
enum GuardFailure: Error, CustomStringConvertible {
    case unavailable(String)
    var description: String {
        switch self { case .unavailable(let detail): return detail }
    }
}

// Pure fixture interface: nil means eligible, a reason means skip.
func eligibility(candidate: SnapshotCandidate, in snapshot: GuardSnapshot) -> String? {
    guard snapshot.candidates.contains(candidate) else { return "candidate-disappeared" }
    guard snapshot.frontmostPID > 0 else { return "frontmost-unknown" }
    guard !snapshot.hiddenPIDs.contains(candidate.pid) else { return "already-hidden" }
    guard !snapshot.visibleWorkspaces.isEmpty else { return "visible-workspaces-unknown" }
    guard !snapshot.managedWindows.contains(where: { $0.windowID == candidate.windowID }) else {
        return "managed-window"
    }
    guard snapshot.managedWindows.contains(where: { $0.pid == candidate.pid }) else {
        return "no-managed-owner-window"
    }
    guard let evidence = snapshot.axEvidence.first(where: {
        $0.windowID == candidate.windowID && $0.pid == candidate.pid
    }), evidence.isSnapshot else { return "snapshot-ax-signature-unproven" }
    guard !snapshot.nativeDisplays.isEmpty else { return "native-spaces-unknown" }
    for display in snapshot.nativeDisplays {
        guard let current = display.spaces.first(where: { $0.id == display.currentSpaceID }) else {
            return "native-current-space-unknown"
        }
        guard current.type == 0 else { return "native-fullscreen-or-special-space-visible" }
    }
    // A snapshot can survive destruction of its native Space. Its own AX
    // signature, not the continued existence of that Space, proves eligibility.
    guard !snapshot.nativeDisplays.contains(where: { display in
        display.spaces.contains { space in
            space.fullscreenWindowID == candidate.windowID
                || space.windows.contains { $0.windowID == candidate.windowID }
        }
    }) else { return "native-fullscreen-window" }
    return nil
}
func stableContext(_ first: GuardSnapshot, _ second: GuardSnapshot) -> Bool {
    first.frontmostPID == second.frontmostPID
        && first.visibleWorkspaces == second.visibleWorkspaces
        && first.nativeDisplays == second.nativeDisplays
        && first.managedWindows == second.managedWindows
        && first.axEvidence == second.axEvidence
}

func activeDisplayBounds() throws -> [CGRect] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
        throw GuardFailure.unavailable("display-list-unavailable")
    }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
        throw GuardFailure.unavailable("display-list-unavailable")
    }
    return displays.prefix(Int(count)).map(CGDisplayBounds)
}
func scanCandidates() throws -> [SnapshotCandidate] {
    let displayBounds = try activeDisplayBounds()
    guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
        as? [[String: Any]] else { throw GuardFailure.unavailable("onscreen-windows-unavailable") }
    let owners = Set(["Discord", "Firefox", "Firefox Developer Edition"])
    var result: [SnapshotCandidate] = []
    for window in windows {
        guard let owner = window[kCGWindowOwnerName as String] as? String,
              owners.contains(owner),
              (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { continue }
        let name = (window[kCGWindowName as String] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? NSNumber, let y = bounds["Y"] as? NSNumber,
              let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber
        else { continue }
        let rect = CGRect(x: x.doubleValue, y: y.doubleValue,
                          width: width.doubleValue, height: height.doubleValue)
        guard displayBounds.contains(where: {
            abs($0.minX - rect.minX) <= 1 && abs($0.minY - rect.minY) <= 1
                && abs($0.width - rect.width) <= 1 && abs($0.height - rect.height) <= 1
        }), let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
            let windowID = window[kCGWindowNumber as String] as? NSNumber,
            pid.int32Value > 0, windowID.uint32Value > 0 else { continue }
        result.append(SnapshotCandidate(pid: pid.int32Value, owner: owner,
                                        windowID: windowID.uint32Value))
    }
    return result.sorted { $0.windowID < $1.windowID }
}

func snapshotAXWindow(_ candidate: SnapshotCandidate) throws -> AXUIElement {
    let app = AXUIElementCreateApplication(candidate.pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else {
        throw GuardFailure.unavailable("ax-windows-unavailable")
    }
    for window in windows {
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(window, &id) == .success && id == candidate.windowID {
            AXUIElementSetMessagingTimeout(window, 0.5)
            return window
        }
    }
    throw GuardFailure.unavailable("ax-window-unavailable")
}
func readAXEvidence(_ candidate: SnapshotCandidate, window: AXUIElement) throws -> SnapshotAXEvidence {
    func attribute<T>(_ key: String) throws -> T {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, key as CFString, &value) == .success,
              let result = value as? T else {
            throw GuardFailure.unavailable("ax-attribute-unavailable:\(key)")
        }
        return result
    }
    func settable(_ key: String) throws -> Bool {
        var value = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, key as CFString, &value) == .success else {
            throw GuardFailure.unavailable("ax-settable-unavailable:\(key)")
        }
        return value.boolValue
    }
    var closeButton: CFTypeRef?
    let closeStatus = AXUIElementCopyAttributeValue(window, "AXCloseButton" as CFString, &closeButton)
    let children: [AXUIElement] = try attribute("AXChildren")
    return try SnapshotAXEvidence(windowID: candidate.windowID, pid: candidate.pid,
        role: attribute("AXRole"), subrole: attribute("AXSubrole"), title: attribute("AXTitle"),
        childCount: children.count, focused: attribute("AXFocused"), main: attribute("AXMain"),
        fullscreen: attribute("AXFullScreen"), minimized: attribute("AXMinimized"),
        closeButtonAbsent: closeStatus == .noValue || closeStatus == .attributeUnsupported,
        positionSettable: settable("AXPosition"), sizeSettable: settable("AXSize"),
        minimizedSettable: settable("AXMinimized"), fullscreenSettable: settable("AXFullScreen"))
}

func readNativeDisplays() throws -> [NativeDisplay] {
    guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                              RTLD_LAZY | RTLD_LOCAL) else {
        throw GuardFailure.unavailable("native-space-api-unavailable")
    }
    defer { dlclose(library) }
    guard let mainSymbol = dlsym(library, "SLSMainConnectionID"),
          let copySymbol = dlsym(library, "SLSCopyManagedDisplaySpaces") else {
        throw GuardFailure.unavailable("native-space-api-unavailable")
    }
    typealias MainConnection = @convention(c) () -> Int32
    typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    let mainConnection = unsafeBitCast(mainSymbol, to: MainConnection.self)
    let copyDisplays = unsafeBitCast(copySymbol, to: CopyDisplays.self)
    guard let raw = copyDisplays(mainConnection())?.takeRetainedValue(),
          let records = raw as NSArray as? [[String: Any]], !records.isEmpty else {
        throw GuardFailure.unavailable("native-spaces-unavailable")
    }
    var result: [NativeDisplay] = []
    for record in records {
        guard let identifier = record["Display Identifier"] as? String,
              let current = record["Current Space"] as? [String: Any],
              let currentID = current["ManagedSpaceID"] as? NSNumber,
              let rawSpaces = record["Spaces"] as? [[String: Any]], !rawSpaces.isEmpty else {
            throw GuardFailure.unavailable("native-space-schema-unknown")
        }
        var spaces: [NativeSpace] = []
        for rawSpace in rawSpaces {
            guard let id = rawSpace["ManagedSpaceID"] as? NSNumber,
                  let type = rawSpace["type"] as? NSNumber else {
                throw GuardFailure.unavailable("native-space-schema-unknown")
            }
            let manager = rawSpace["TileLayoutManager"] as? [String: Any]
            let tiles = manager?["TileSpaces"] as? [[String: Any]] ?? []
            var windows: [NativeFullscreenWindow] = []
            for tile in tiles {
                guard let pid = tile["pid"] as? NSNumber,
                      let window = tile["TileWindowID"] as? NSNumber else {
                    throw GuardFailure.unavailable("native-fullscreen-schema-unknown")
                }
                windows.append(NativeFullscreenWindow(windowID: window.uint32Value,
                                                       pid: pid.int32Value))
            }
            spaces.append(NativeSpace(id: id.uint64Value, type: type.intValue,
                fullscreenWindowID: (rawSpace["fs_wid"] as? NSNumber)?.uint32Value,
                windows: windows.sorted { $0.windowID < $1.windowID }))
        }
        guard spaces.contains(where: { $0.id == currentID.uint64Value }) else {
            throw GuardFailure.unavailable("native-current-space-unknown")
        }
        result.append(NativeDisplay(identifier: identifier, currentSpaceID: currentID.uint64Value,
                                    spaces: spaces.sorted { $0.id < $1.id }))
    }
    return result.sorted { $0.identifier < $1.identifier }
}

// Temporary output avoids pipe-buffer deadlocks. Each subprocess has a hard
// timeout; only this helper's own child is killed on expiry. No shell is used.
func aerospaceJSON(_ arguments: [String]) throws -> [[String: Any]] {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("aerospace-ghost-scan-\(UUID().uuidString)")
    guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                        attributes: [.posixPermissions: 0o600]) else {
        throw GuardFailure.unavailable("aerospace-output-unavailable")
    }
    defer { try? FileManager.default.removeItem(at: url) }
    let output = try FileHandle(forWritingTo: url)
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/aerospace")
    process.arguments = arguments + ["--json"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let deadline = ProcessInfo.processInfo.systemUptime + 0.8
    while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        throw GuardFailure.unavailable("aerospace-query-timeout")
    }
    guard process.terminationStatus == 0 else {
        throw GuardFailure.unavailable("aerospace-query-failed")
    }
    let data = try Data(contentsOf: url)
    guard data.count <= 1_048_576,
          let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw GuardFailure.unavailable("aerospace-response-invalid")
    }
    return value
}
func readVisibleWorkspaces() throws -> [String] {
    let records = try aerospaceJSON(["list-workspaces", "--monitor", "all", "--visible",
                                      "--format", "%{workspace}"])
    var workspaces: [String] = []
    for record in records {
        guard let workspace = record["workspace"] as? String, !workspace.isEmpty else {
            throw GuardFailure.unavailable("visible-workspaces-invalid")
        }
        workspaces.append(workspace)
    }
    guard !workspaces.isEmpty else { throw GuardFailure.unavailable("visible-workspaces-unknown") }
    return Array(Set(workspaces)).sorted()
}
func captureSnapshot() throws -> GuardSnapshot {
    // AppKit caches time-varying properties until the next run-loop turn.
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    guard let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
        throw GuardFailure.unavailable("frontmost-unknown")
    }
    let native = try readNativeDisplays()
    let visible = try readVisibleWorkspaces()
    let records = try aerospaceJSON(["list-windows", "--all", "--format",
                                      "%{window-id} %{app-pid} %{workspace}"])
    var managed: [ManagedWindow] = []
    for record in records {
        guard let id = record["window-id"] as? NSNumber,
              let pid = record["app-pid"] as? NSNumber,
              let workspace = record["workspace"] as? String else {
            throw GuardFailure.unavailable("managed-windows-invalid")
        }
        managed.append(ManagedWindow(windowID: id.uint32Value, pid: pid.int32Value,
                                      workspace: workspace))
    }
    let candidates = try scanCandidates()
    let evidence = candidates.compactMap { candidate -> SnapshotAXEvidence? in
        guard let window = try? snapshotAXWindow(candidate) else { return nil }
        return try? readAXEvidence(candidate, window: window)
    }
    let hidden = NSWorkspace.shared.runningApplications.filter(\.isHidden)
        .map(\.processIdentifier).sorted()
    guard visible == (try readVisibleWorkspaces()), native == (try readNativeDisplays()),
          frontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
        throw GuardFailure.unavailable("desktop-changed-during-sample")
    }
    return GuardSnapshot(candidates: candidates, axEvidence: evidence,
        managedWindows: managed.sorted { $0.windowID < $1.windowID }, visibleWorkspaces: visible,
        frontmostPID: frontmost, hiddenPIDs: hidden, nativeDisplays: native)
}
func emit(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
}
func candidateDescription(_ candidate: SnapshotCandidate, in snapshot: GuardSnapshot) -> [String: Any] {
    let reason = eligibility(candidate: candidate, in: snapshot)
    return ["pid": candidate.pid, "app": candidate.owner, "window_id": candidate.windowID,
            "eligible": reason == nil, "reason": reason ?? "eligible"]
}
func guardOnce() throws -> Int32 {
    let first = try captureSnapshot()
    guard let candidate = first.candidates.first(where: { eligibility(candidate: $0, in: first) == nil }) else {
        emit(["status": "skipped", "reason": "no-eligible-candidate",
              "candidates": first.candidates.map { candidateDescription($0, in: first) }])
        return 0
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35))
    let second = try captureSnapshot()
    guard stableContext(first, second), eligibility(candidate: candidate, in: second) == nil else {
        emit(["status": "state-changed", "reason": "desktop-or-candidate-changed"])
        return 0
    }
    let window = try snapshotAXWindow(candidate)
    let bounds = try activeDisplayBounds()
    let final = try captureSnapshot()
    guard stableContext(second, final), eligibility(candidate: candidate, in: final) == nil,
          let evidence = try? readAXEvidence(candidate, window: window), evidence.isSnapshot,
          final.axEvidence.contains(evidence), bounds == (try activeDisplayBounds()),
          let app = NSRunningApplication(processIdentifier: candidate.pid),
          !app.isHidden, !app.isTerminated,
          NSWorkspace.shared.frontmostApplication?.processIdentifier == final.frontmostPID else {
        emit(["status": "state-changed", "reason": "desktop-or-candidate-changed"])
        return 0
    }
    // Moving only this childless, noninteractive AXUnknown window works even
    // when its owner is foreground. Keep its original size and place it beyond
    // every active display, including monitors with negative origins.
    var destination = CGPoint(x: bounds.map(\.maxX).max()! + 64,
                              y: bounds.map(\.maxY).max()! + 64)
    guard let position = AXValueCreate(.cgPoint, &destination),
          AXUIElementSetAttributeValue(window, "AXPosition" as CFString, position) == .success else {
        emit(["status": "failed", "reason": "snapshot-move-failed", "window_id": candidate.windowID])
        return 1
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
    // kCGWindowIsOnscreen means membership in a visible Space, even when the
    // entire rectangle is outside the physical displays. Verify intersection.
    var outsideDisplays = false
    if let rows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]],
       let afterBounds = try? activeDisplayBounds() {
        if let row = rows.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == candidate.windowID
                && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == candidate.pid
        }) {
            if let raw = row[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: raw) {
                outsideDisplays = !afterBounds.contains { $0.intersects(rect) }
            }
        } else {
            outsideDisplays = true
        }
    }
    let nativePreserved = (try? readNativeDisplays()) == final.nativeDisplays
    let focusPreserved = NSWorkspace.shared.frontmostApplication?.processIdentifier == final.frontmostPID
    let succeeded = outsideDisplays && nativePreserved && focusPreserved && !app.isHidden
    emit(["status": succeeded ? "quarantined" : "failed",
          "pid": candidate.pid, "app": candidate.owner, "window_id": candidate.windowID,
          "outside_displays": outsideDisplays, "app_unhidden": !app.isHidden,
          "native_state_unchanged": nativePreserved, "focus_unchanged": focusPreserved])
    return succeeded ? 0 : 1
}

func snapshotScannerMain() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    do {
        if arguments.isEmpty {
            var reported = Set<Int32>()
            for candidate in try scanCandidates() where reported.insert(candidate.pid).inserted {
                print("\(candidate.pid)\t\(candidate.owner)\t\(candidate.windowID)")
            }
        } else if arguments == ["--inspect"] || arguments == ["--dry-run"] {
            let snapshot = try captureSnapshot()
            emit(["status": "inspected", "visible_workspaces": snapshot.visibleWorkspaces,
                  "frontmost_pid": snapshot.frontmostPID,
                  "candidates": snapshot.candidates.map { candidateDescription($0, in: snapshot) }])
        } else if arguments == ["--guard"] {
            exit(try guardOnce())
        } else {
            emit(["status": "failed", "reason": "usage: [--inspect|--dry-run|--guard]"])
            exit(2)
        }
    } catch {
        let reason = String(describing: error)
        emit(["status": reason == "desktop-changed-during-sample" ? "state-changed" : "skipped",
              "reason": reason])
        exit(reason == "desktop-changed-during-sample" ? 0 : 1)
    }
}

snapshotScannerMain()
