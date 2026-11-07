#if NATIVE_LIVE_ACTIVITIES
import AppKit
import Foundation

@MainActor
enum BackgroundHandoffVerification {
    @MainActor private final class ActivationTrace {
        var bundleIDs: [String] = []
    }

    static func run(store: AgentStore) async -> [String: Any] {
        var report: [String: Any] = ["passed": false]
        do {
            let snapshot = try await store.client.snapshot()
            guard let pane = snapshot.focusedPaneID, snapshot.trackedAgents.contains(where: { $0.id == pane }) else {
                throw HerdrError.message("The focused pane must be a tracked agent to verify handoff without changing the user's selection.")
            }
            await store.refreshTerminals()
            let terminal = try store.terminal.prepareFocus(paneID: pane, preferredBundleID: store.terminalBundleID).client.application
            try await store.terminal.activate(preferredBundleID: store.terminalBundleID, paneID: pane)
            for _ in 0..<30 {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == terminal.bundleID && !NSApp.isActive { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard !NSApp.isActive, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == terminal.bundleID else {
                throw HerdrError.message("Could not establish the terminal as the foreground application.")
            }
            let trace = ActivationTrace()
            let center = NSWorkspace.shared.notificationCenter
            let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let id = app.bundleIdentifier {
                    MainActor.assumeIsolated { trace.bundleIDs.append(id) }
                }
            }
            defer { center.removeObserver(observer) }
            report["frontmostBefore"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            guard let agent = store.agents.first(where: { $0.paneID == pane && !$0.isHookSession }) else {
                throw HerdrError.message("The scoped agent is no longer available.")
            }
            try await AgentFocusAction.perform(agentID: agent.id)
            try await Task.sleep(for: .milliseconds(500))
            let after = try await store.client.snapshot()
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let flashed = trace.bundleIDs.contains(Bundle.main.bundleIdentifier ?? "dev.local.dynamicagents") || NSApp.isActive
            report["activations"] = trace.bundleIDs
            report["appActivatedDuringHandoff"] = flashed
            report["frontmostAfter"] = frontmost
            report["paneBefore"] = pane
            report["paneAfter"] = after.focusedPaneID ?? ""
            await store.refreshTerminals()
            let exactWindow = try await store.terminal.agentIsFocused(paneID: agent.paneID, preferredBundleID: store.terminalBundleID)
            report["exactWindowVerified"] = exactWindow
            report["passed"] = !flashed && exactWindow && frontmost == terminal.bundleID && after.focusedPaneID == pane && store.actionError == nil
            report["error"] = store.actionError ?? ""
        } catch { report["error"] = error.localizedDescription }
        return report
    }
}
#endif
