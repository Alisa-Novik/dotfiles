import AppKit
import Foundation

// An empty AeroSpace workspace has no window for AppKit to activate. Give it
// a transparent, borderless accessory window on the ordinary macOS desktop.
// Accessory windows without a close button are excluded by AeroSpace's window
// heuristic. No native Space APIs, synthetic input, or fullscreen changes.

func validWorkspace(_ value: String) -> Bool {
    (1...10).map(String.init).contains(value)
}

let emptyWorkspaceQuery = [
    "list-workspaces", "--monitor", "focused", "--visible", "--empty",
    "--format", "%{workspace}",
]

func stillRequested(_ workspace: String, query: ([String]) -> String?) -> Bool {
    validWorkspace(workspace) && query(emptyWorkspaceQuery)?
        .trimmingCharacters(in: .whitespacesAndNewlines) == workspace
}

func requestedWorkspace(_ url: URL) -> String? {
    guard url.scheme == "aerospace-empty-desktop", url.host == "workspace",
          url.query == nil, url.fragment == nil else { return nil }
    let workspace = String(url.path.dropFirst())
    return validWorkspace(workspace) ? workspace : nil
}

func aerospaceQuery(_ arguments: [String]) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/aerospace")
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let deadline = ProcessInfo.processInfo.systemUptime + 0.8
    while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
        Thread.sleep(forTimeInterval: 0.005)
    }
    guard !process.isRunning else {
        process.terminate()
        return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    // The query returns at most one short workspace name, never a window dump.
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DesktopDelegate: NSObject, NSApplicationDelegate {
    private var desktopWindow: DesktopWindow?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last, let workspace = requestedWorkspace(url),
              stillRequested(workspace, query: aerospaceQuery) else { return }

        if desktopWindow == nil {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            let window = DesktopWindow(
                contentRect: NSRect(x: screen.midX, y: screen.midY, width: 1, height: 1),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.animationBehavior = .none
            // Never join another application's native fullscreen Space.
            window.collectionBehavior = [.managed, .primary, .fullScreenNone, .ignoresCycle]
            desktopWindow = window
        }

        // Creation or launch may have taken time. A later navigation request
        // or a newly opened app cancels this action, with no delayed retry.
        guard stillRequested(workspace, query: aerospaceQuery),
              let window = desktopWindow else { return }
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Only an explicit workspace URL is allowed to activate this window.
        false
    }
}

func selfTest() {
    var calls = [[String]]()
    let emptySix: ([String]) -> String? = { calls.append($0); return "6\n" }
    precondition(stillRequested("6", query: emptySix))
    precondition(calls == [emptyWorkspaceQuery])
    precondition(!stillRequested("6", query: { _ in "" })) // occupied workspace
    precondition(!stillRequested("6", query: { _ in "3\n" })) // newer navigation
    precondition(!stillRequested("6", query: { _ in nil })) // server unavailable
    precondition(!stillRequested("6", query: { _ in "6\n7\n" })) // ambiguous result
    for invalid in ["", "0", "11", "--help", "6; touch /tmp/unwanted", "6\n"] {
        precondition(!stillRequested(invalid, query: { _ in preconditionFailure("invalid input queried server") }))
    }
    for n in 1...10 {
        let url = URL(string: "aerospace-empty-desktop://workspace/\(n)")!
        precondition(requestedWorkspace(url) == String(n))
    }
    for bad in ["https://workspace/6", "aerospace-empty-desktop://wrong/6",
                "aerospace-empty-desktop://workspace/6/7",
                "aerospace-empty-desktop://workspace/6?activate=1"] {
        precondition(requestedWorkspace(URL(string: bad)!) == nil)
    }
    print("PASS: empty workspace, stale request, occupied workspace, failure, and URL guards")
}

if CommandLine.arguments.dropFirst() == ["--self-test"] {
    // No NSApplication instance, window creation, or live AeroSpace calls.
    selfTest()
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = DesktopDelegate()
    application.delegate = delegate
    application.run()
}
