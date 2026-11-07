#if NATIVE_LIVE_ACTIVITIES
import AppKit
import Foundation

@MainActor
enum LiveActivityVerification {
    static func run(store: AgentStore, reportURL: URL) async {
        let originalEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled")
        defer {
            if let originalEnabled { UserDefaults.standard.set(originalEnabled, forKey: "liveActivityEnabled") }
            else { UserDefaults.standard.removeObject(forKey: "liveActivityEnabled") }
        }
        var report: [String: Any] = ["passed": false]
        do {
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<30 {
                if NSApp.isActive { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard NSApp.isActive else { throw AgentError.message("The verification app did not become active before starting the activity.") }
            await store.refresh()
            let initial = store.activityState
            guard initial.total > 0 else { throw AgentError.message("A running agent is required for native verification.") }
            await store.liveActivity.finish()
            report["agentCount"] = initial.total
            let verifier = LiveActivityController()
            await verifier.start(state: initial)
            guard verifier.isRunning, let status = verifier.status, let activityID = status.activityID, status.activeCount == 1 else {
                throw AgentError.message(verifier.message ?? "ActivityKit did not return an active activity.")
            }
            report["authorized"] = status.authorized
            report["startedID"] = activityID
            report["startedState"] = "active"
            await store.refresh()
            let updated = store.activityState
            let beforeUpdate = Date.now
            await verifier.update(updated, force: true)
            for _ in 0..<20 {
                if verifier.status?.state == updated && (verifier.status?.staleDate ?? .distantPast) > beforeUpdate.addingTimeInterval(80) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            report["updated"] = verifier.status?.state == updated && (verifier.status?.staleDate ?? .distantPast) > beforeUpdate.addingTimeInterval(80)
            report["observedStaleDate"] = verifier.status?.staleDate?.timeIntervalSince1970
            await verifier.stop()
            report["ended"] = !verifier.isRunning && verifier.status?.activeCount == 0
            report["endedState"] = "ended"
            await store.liveActivity.start(state: updated)
            let empty = AgentActivityState(agents: [])
            await store.liveActivity.update(empty)
            report["hiddenWhenEmpty"] = !store.liveActivity.isRunning && store.liveActivity.isEnabled && store.liveActivity.status?.activeCount == 0
            let handoff = await BackgroundHandoffVerification.run(store: store)
            report["backgroundHandoff"] = handoff
            report["resumedInBackground"] = store.liveActivity.isRunning && !NSApp.isActive
            report["monitoring"] = store.liveActivity.isRunning
            report["activeCount"] = store.liveActivity.status?.activeCount ?? 0
            report["monitoringID"] = store.liveActivity.status?.activityID ?? ""
            report["passed"] = report["updated"] as? Bool == true && report["ended"] as? Bool == true && report["hiddenWhenEmpty"] as? Bool == true && report["resumedInBackground"] as? Bool == true && handoff["passed"] as? Bool == true
            report["error"] = store.liveActivity.message ?? ""
            store.start()
        } catch { report["error"] = error.localizedDescription }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        } catch { FileHandle.standardError.write(Data("Unable to write Live Activity report: \(error)\n".utf8)) }
    }
}
#endif
