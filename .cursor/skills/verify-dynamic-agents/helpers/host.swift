import AppKit
import Foundation

@main
struct FixtureHost {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = HostDelegate(root: URL(fileURLWithPath: CommandLine.arguments[1]))
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class HostDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let root: URL
    var windows: [NSWindow] = []
    var timer: Timer?
    var token = -1
    var lastKey = ""
    var activations = 0
    var error = ""
    init(root: URL) { self.root = root }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for index in 1...2 {
            let window = NSWindow(contentRect: NSRect(x: 180 + index * 30, y: 160, width: 400, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.identifier = NSUserInterfaceItemIdentifier("fixture-window-\(index)")
            window.title = "Verification Host \(index)"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = NSTextField(labelWithString: "Controlled lifecycle fixture")
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        lastKey = "fixture-window-2"
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        publish()
    }
    func applicationDidBecomeActive(_ notification: Notification) { activations += 1; publish() }
    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow { lastKey = window.identifier?.rawValue ?? "" }
        publish()
    }
    func tick() {
        let file = root.appendingPathComponent("host-command.json")
        if let data = try? Data(contentsOf: file), data.count <= 65_536,
           let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let next = request["token"] as? Int, next != token,
           let events = request["events"] as? [[String: Any]] {
            error = ""
            for event in events {
                do { try report(event) } catch { self.error = error.localizedDescription }
            }
            token = next
        }
        publish()
    }
    func report(_ event: [String: Any]) throws {
        guard let source = event["source"] as? String, ["pi", "claude", "codex", "cursor", "copilot"].contains(source),
              let name = event["event"] as? String, let payload = event["payload"] as? [String: Any] else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("desktop-data/desktop-hook.py").path, "report", source, name]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: payload))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Lifecycle reporter failed"]) }
    }
    func publish() {
        let value: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "lastKeyWindow": lastKey,
                                    "windowCount": windows.count, "activations": activations, "completedToken": token, "error": error]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("host-state.json"), options: .atomic)
        }
    }
}
