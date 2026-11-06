#if NATIVE_LIVE_ACTIVITIES
import AppKit
@preconcurrency import ActivityKit
import Foundation

@MainActor
enum LiveActivityVerification {
    static func run(store: AgentStore, reportURL: URL) async {
        var report: [String: Any] = ["passed": false]
        do {
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<30 {
                if NSApp.isActive { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard NSApp.isActive else { throw HerdrError.message("The verification app did not become active before starting the activity.") }
            let snapshot = try await store.client.snapshot()
            var feed = AgentActivityFeed()
            feed.observe(snapshot.trackedAgents, at: .now)
            let initial = AgentActivityState(agents: feed.agents(from: snapshot.trackedAgents, at: .now), workspaces: snapshot.workspaces, prioritizeRunning: true, itemLimit: .max)
            guard initial.total > 0 else { throw HerdrError.message("A running agent is required for native verification.") }
            await store.liveActivity.finish()
            report["authorized"] = ActivityAuthorizationInfo().areActivitiesEnabled
            report["agentCount"] = initial.total
            let verifier = LiveActivityController()
            await verifier.start(state: initial, session: store.session)
            guard verifier.isRunning,
                  let activity = Activity<AgentActivityAttributes>.activities.first(where: { $0.activityState == .active }) else {
                throw HerdrError.message(verifier.message ?? "ActivityKit did not return an active activity.")
            }
            report["startedID"] = activity.id
            report["startedState"] = String(describing: activity.activityState)
            let latest = try await store.client.snapshot()
            feed.observe(latest.trackedAgents, at: .now)
            let updated = AgentActivityState(agents: feed.agents(from: latest.trackedAgents, at: .now), workspaces: latest.workspaces, prioritizeRunning: true, itemLimit: .max)
            let staleDate = Date.now.addingTimeInterval(120)
            await activity.update(ActivityContent(state: updated, staleDate: staleDate))
            for _ in 0..<20 {
                if activity.content.state == updated && abs((activity.content.staleDate ?? .distantPast).timeIntervalSince(staleDate)) < 1 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            report["updated"] = activity.content.state == updated && abs((activity.content.staleDate ?? .distantPast).timeIntervalSince(staleDate)) < 1
            report["requestedStaleDate"] = staleDate.timeIntervalSince1970
            report["observedStaleDate"] = activity.content.staleDate?.timeIntervalSince1970
            await verifier.stop()
            report["ended"] = !Activity<AgentActivityAttributes>.activities.contains { $0.id == activity.id && ($0.activityState == .active || $0.activityState == .stale) }
            report["endedState"] = String(describing: activity.activityState)
            await store.liveActivity.start(state: updated, session: store.session)
            let empty = AgentActivityState(agents: [], workspaces: [])
            await store.liveActivity.update(empty, session: store.session)
            report["hiddenWhenEmpty"] = !store.liveActivity.isRunning && store.liveActivity.isEnabled && !Activity<AgentActivityAttributes>.activities.contains { $0.activityState == .active }
            let handoff = await BackgroundHandoffVerification.run(store: store)
            report["backgroundHandoff"] = handoff
            report["resumedInBackground"] = store.liveActivity.isRunning && !NSApp.isActive
            report["monitoring"] = store.liveActivity.isRunning
            report["activeCount"] = Activity<AgentActivityAttributes>.activities.filter { $0.activityState == .active }.count
            report["monitoringID"] = Activity<AgentActivityAttributes>.activities.first { $0.activityState == .active }?.id ?? ""
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
