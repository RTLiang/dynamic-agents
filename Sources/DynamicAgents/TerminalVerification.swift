import AppKit
import Foundation
#if SWIFT_PACKAGE
import AgentCore
#endif

@MainActor
enum TerminalVerification {
    static func run(reportURL: URL) async {
        var report: [String: Any] = ["passed": false]
        do {
            let store = AgentStore()
            await store.refresh()
            await store.refreshTerminals()
            let before = try await store.client.snapshot()
            guard let pane = before.focusedPaneID, let agent = store.agents.first(where: { $0.paneID == pane }) else {
                throw HerdrError.message("No focused agent is available for a non-disruptive focus check.")
            }
            guard store.terminalBundleID.isEmpty else {
                throw HerdrError.message("The zero-configuration check requires automatic mode and one detected terminal.")
            }
            let anchor = try TerminalClientSelection.client(from: store.terminal.clients, paneID: agent.paneID, preferredBundleID: "", preferredClientID: store.terminal.preferredClientID)
            let surfaces = try TerminalAutomation.surfaces(in: anchor.application)
            report["clientTTY"] = anchor.tty ?? ""
            report["clientPID"] = anchor.processID
            report["surfaces"] = surfaces.map { ["id": $0.id, "windowID": $0.windowID, "tty": $0.tty, "processID": String($0.processID ?? 0)] }
            let detected = try store.terminal.prepareFocus(paneID: agent.paneID, preferredBundleID: "").client.application
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(300))
            let initialFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            await store.focus(agent)
            try await Task.sleep(for: .milliseconds(300))
            let actual = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let after = try await store.client.snapshot()
            await store.refreshTerminals()
            let exactWindow = try await store.terminal.agentIsFocused(paneID: agent.paneID, preferredBundleID: "")
            let afterSurfaces = try TerminalAutomation.surfaces(in: detected)
            let unchangedViews = Set(surfaces.map(\.id)) == Set(afterSurfaces.map(\.id))
            report = [
                "passed": store.actionError == nil && initialFrontmost == Bundle.main.bundleIdentifier && actual == detected.bundleID && exactWindow && unchangedViews && after.focusedPaneID == pane,
                "exactWindowVerified": exactWindow,
                "terminalViewsUnchanged": unchangedViews,
                "automatic": true,
                "detectedApp": detected.name,
                "detectedBundleID": detected.bundleID,
                "detectedPID": detected.pid,
                "frontmostBefore": initialFrontmost,
                "frontmostAfter": actual,
                "focusedPaneBefore": pane,
                "focusedPaneAfter": after.focusedPaneID ?? "",
                "error": store.actionError ?? ""
            ]
        } catch { report["error"] = error.localizedDescription }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        } catch { FileHandle.standardError.write(Data("Unable to write terminal verification report: \(error)\n".utf8)) }
    }
}
