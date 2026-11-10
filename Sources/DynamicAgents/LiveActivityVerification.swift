#if NATIVE_LIVE_ACTIVITIES
import AppKit
@preconcurrency import ActivityKit
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
        var ownedVerifier: LiveActivityController?
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
            ownedVerifier = verifier
            await verifier.start(state: initial)
            for _ in 0..<30 {
                if verifier.status?.activeCount == 1 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
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
            if let external = Activity<AgentActivityAttributes>.activities.first(where: { $0.id == activityID }) {
                await external.end(nil, dismissalPolicy: .after(Date.now.addingTimeInterval(60)))
                for _ in 0..<25 {
                    if !verifier.isRunning { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                try await Task.sleep(for: .milliseconds(2100))
                await verifier.update(updated, force: true)
                report["systemEndRecovered"] = verifier.isEnabled && verifier.isRunning && verifier.status?.activityID != activityID && verifier.status?.activeCount == 1
            } else { report["systemEndRecovered"] = false }
            let beforeRestart = verifier.status?.activityID
            await verifier.restart(state: updated)
            report["manualRestarted"] = verifier.isEnabled && verifier.isRunning && verifier.status?.activityID != beforeRestart && verifier.status?.activeCount == 1
            await verifier.stop()
            report["ended"] = !verifier.isRunning && verifier.status?.activeCount == 0
            report["endedState"] = "ended"
            await store.liveActivity.start(state: updated)
            let empty = AgentActivityState(agents: [])
            await store.liveActivity.update(empty)
            report["hiddenWhenEmpty"] = !store.liveActivity.isRunning && store.liveActivity.isEnabled && store.liveActivity.status?.activeCount == 0
            NSApp.hide(nil)
            for _ in 0..<30 {
                if !NSApp.isActive { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard !NSApp.isActive else { throw AgentError.message("Unable to background the main App for the creation check.") }
            let creationBeganInBackground = !NSApp.isActive && store.liveActivity.status?.activeCount == 0
            await store.liveActivity.update(updated, force: true)
            for _ in 0..<30 {
                if store.liveActivity.status?.activeCount == 1 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            report["createdInBackground"] = creationBeganInBackground && !NSApp.isActive && store.liveActivity.isRunning && store.liveActivity.status?.activeCount == 1
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<30 {
                if NSApp.isActive { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let handoff = await BackgroundHandoffVerification.run(store: store)
            report["backgroundHandoff"] = handoff
            report["resumedInBackground"] = store.liveActivity.isRunning && !NSApp.isActive
            report["monitoring"] = store.liveActivity.isRunning
            report["activeCount"] = store.liveActivity.status?.activeCount ?? 0
            report["monitoringID"] = store.liveActivity.status?.activityID ?? ""
            report["lifecyclePassed"] = report["updated"] as? Bool == true && report["systemEndRecovered"] as? Bool == true && report["manualRestarted"] as? Bool == true && report["createdInBackground"] as? Bool == true && report["ended"] as? Bool == true && report["hiddenWhenEmpty"] as? Bool == true && report["resumedInBackground"] as? Bool == true
            report["passed"] = report["lifecyclePassed"] as? Bool == true && handoff["passed"] as? Bool == true
            report["error"] = store.liveActivity.message ?? ""
        } catch { report["error"] = error.localizedDescription }
        if let ownedVerifier, ownedVerifier.isRunning { await ownedVerifier.stop() }
        if originalEnabled as? Bool ?? true { await store.liveActivity.start(state: store.activityState) }
        else { await store.liveActivity.stop() }
        store.start()
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        } catch { FileHandle.standardError.write(Data("Unable to write Live Activity report: \(error)\n".utf8)) }
    }
}
#endif
