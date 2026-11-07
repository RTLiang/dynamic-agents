import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif
#if NATIVE_LIVE_ACTIVITIES
@preconcurrency import ActivityKit
#endif

struct LiveActivitySnapshot {
    let authorized: Bool
    let activityID: String?
    let activeCount: Int
    let state: AgentActivityState?
    let staleDate: Date?
}

@Observable @MainActor
final class LiveActivityController {
    private(set) var isEnabled = false
    private(set) var isRunning = false
    private(set) var isStarting = false
    private var generation = 0
    private var stateTask: Task<Void, Never>?
    private(set) var message: String?
    private var lastState: AgentActivityState?
    private var lastUpdate = Date.distantPast
    var isSupported: Bool {
        #if NATIVE_LIVE_ACTIVITIES
        if #available(macOS 27.3, *) { return true }
        #endif
        return false
    }

    #if NATIVE_LIVE_ACTIVITIES
    private var activity: Activity<AgentActivityAttributes>?

    init() {
        activity = Activity<AgentActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
        isRunning = activity != nil
        isEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
        if let activity { observe(activity) }
    }
    #else
    init() { message = L10n.text("Live Activities require the native app with its widget extension.") }
    #endif

    func start(state: AgentActivityState, session: String) async {
        guard isSupported else { return }
        #if NATIVE_LIVE_ACTIVITIES
        if let activity, activity.activityState == .ended || activity.activityState == .dismissed {
            stateTask?.cancel()
            self.activity = nil
            isRunning = false
        }
        #endif
        isEnabled = true
        UserDefaults.standard.set(true, forKey: "liveActivityEnabled")
        await update(state, session: session)
    }

    func update(_ state: AgentActivityState, session: String, force: Bool = false) async {
        #if NATIVE_LIVE_ACTIVITIES
        guard isEnabled, !isStarting else { return }
        if let activity, activity.activityState != .active && activity.activityState != .stale {
            self.activity = nil
            isRunning = false
            isEnabled = false
            UserDefaults.standard.set(false, forKey: "liveActivityEnabled")
            return
        }
        guard state.connected, state.total > 0 else {
            await hide()
            return
        }
        if let activity {
            guard force || lastState != state || Date.now.timeIntervalSince(lastUpdate) >= 30 else { return }
            await activity.update(ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(90)))
            lastState = state
            lastUpdate = .now
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = L10n.text("Allow Live Activities for Dynamic Agents in System Settings.")
            return
        }
        isStarting = true
        generation += 1
        let requestGeneration = generation
        defer { isStarting = false }
        do {
            for previous in Activity<AgentActivityAttributes>.activities {
                await previous.end(nil, dismissalPolicy: .immediate)
                guard requestGeneration == generation, isEnabled else { return }
            }
            activity = try Activity.request(
                attributes: AgentActivityAttributes(sessionName: session.isEmpty ? L10n.text("Local herdr") : session),
                content: ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(90)),
                pushType: nil
            )
            isRunning = true
            if let activity { observe(activity) }
            lastState = state
            lastUpdate = .now
            message = nil
        } catch { message = error.localizedDescription; isRunning = false }
        #endif
    }

    #if NATIVE_LIVE_ACTIVITIES
    private func observe(_ activity: Activity<AgentActivityAttributes>) {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, self.activity?.id == activity.id else { return }
                if state == .dismissed || state == .ended {
                    self.activity = nil
                    isRunning = false
                    isEnabled = false
                    UserDefaults.standard.set(false, forKey: "liveActivityEnabled")
                    return
                }
            }
        }
    }
    #endif

    private func hide() async {
        generation += 1
        stateTask?.cancel()
        #if NATIVE_LIVE_ACTIVITIES
        let previous = activity
        activity = nil
        isRunning = false
        lastState = nil
        if let previous { await previous.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    func stop() async {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: "liveActivityEnabled")
        await finish()
    }

    var status: LiveActivitySnapshot? {
        #if NATIVE_LIVE_ACTIVITIES
        let activities = Activity<AgentActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        return LiveActivitySnapshot(authorized: ActivityAuthorizationInfo().areActivitiesEnabled, activityID: activity?.id, activeCount: activities.count, state: activity?.content.state, staleDate: activity?.content.staleDate)
        #else
        return nil
        #endif
    }

    func finish() async {
        isEnabled = false
        await hide()
        #if NATIVE_LIVE_ACTIVITIES
        for activity in Activity<AgentActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
