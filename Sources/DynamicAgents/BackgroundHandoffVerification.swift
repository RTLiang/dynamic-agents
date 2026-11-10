#if NATIVE_LIVE_ACTIVITIES
import AppKit
import Foundation

@MainActor
enum BackgroundHandoffVerification {
    @MainActor private final class ActivationTrace { var bundleIDs: [String] = [] }
    static func run(store: AgentStore) async -> [String: Any] {
        var report: [String: Any] = ["passed": false]
        do {
            await store.refresh()
            guard let agent = store.agents.first(where: { $0.hostBundleID != nil && $0.isSessionAvailable }),
                  let bundle = agent.hostBundleID else { throw AgentError.message("A live hook session with an observed host app is required.") }
            await store.focus(agent, presentsError: false)
            for _ in 0..<30 {
                if !NSApp.isActive && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard store.actionError == nil, !NSApp.isActive,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else {
                throw AgentError.message(store.actionError ?? "Could not activate the hook's host app.")
            }
            let trace = ActivationTrace()
            let center = NSWorkspace.shared.notificationCenter
            let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, let id = app.bundleIdentifier {
                    MainActor.assumeIsolated { trace.bundleIDs.append(id) }
                }
            }
            defer { center.removeObserver(observer) }
            let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
            try await AgentFocusAction.perform(agentID: agent.id)
            try await Task.sleep(for: .milliseconds(300))
            let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let flashed = trace.bundleIDs.contains(Bundle.main.bundleIdentifier ?? AgentHandoff.applicationID) || NSApp.isActive
            report["activations"] = trace.bundleIDs
            report["appActivatedDuringHandoff"] = flashed
            report["sameHostProcess"] = before == after
            report["passed"] = !flashed && before == after && store.actionError == nil
            report["error"] = store.actionError ?? ""
        } catch { report["error"] = error.localizedDescription }
        return report
    }
}
#endif
