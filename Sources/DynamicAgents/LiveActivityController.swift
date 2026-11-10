import AppKit
import OSLog
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
    private var lastRequest = Date.distantPast
    private var nextRequest = Date.distantPast
    private var failedRequests = 0
    private var registryMisses = 0
    private var requiresForeground = false
    private let now: () -> Date
    private let isForeground: () -> Bool
    private let logger = Logger(subsystem: "dev.local.dynamicagents", category: "LiveActivityLifecycle")
    var isSupported: Bool {
        #if NATIVE_LIVE_ACTIVITIES
        if #available(macOS 27.3, *) { return true }
        #endif
        return false
    }

    #if NATIVE_LIVE_ACTIVITIES
    private var activity: Activity<AgentActivityAttributes>?

    init(now: @escaping () -> Date = Date.init, isForeground: @escaping () -> Bool = { NSApp?.isActive ?? false }) {
        self.now = now
        self.isForeground = isForeground
        activity = Activity<AgentActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
        isRunning = activity != nil
        isEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
        if let activity { observe(activity) }
        logger.notice("Initialized: enabled=\(self.isEnabled, privacy: .public), tracked=\(self.isRunning, privacy: .public)")
    }
    #else
    init(now: @escaping () -> Date = Date.init, isForeground: @escaping () -> Bool = { NSApp?.isActive ?? false }) {
        self.now = now
        self.isForeground = isForeground
        message = L10n.text("Live Activities require the native app with its widget extension.")
    }
    #endif

    func start(state: AgentActivityState) async {
        guard isSupported else { return }
        #if NATIVE_LIVE_ACTIVITIES
        if let current = activity, current.activityState == .ended || current.activityState == .dismissed {
            clearTrackedActivity()
        }
        #endif
        isEnabled = true
        nextRequest = .distantPast
        failedRequests = 0
        requiresForeground = false
        UserDefaults.standard.set(true, forKey: "liveActivityEnabled")
        await update(state, force: true)
    }

    func retryIfNeeded(state: AgentActivityState) async {
        guard isEnabled, !isRunning, !isStarting else { return }
        nextRequest = .distantPast
        logger.notice("Retrying pending creation after foreground activation")
        await update(state)
    }

    func restart(state: AgentActivityState) async {
        guard isSupported else { return }
        logger.notice("Explicit restart requested")
        await hide()
        await start(state: state)
    }

    func update(_ state: AgentActivityState, force: Bool = false) async {
        #if NATIVE_LIVE_ACTIVITIES
        guard isEnabled, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let updateGeneration = generation

        if let current = activity {
            if current.activityState == .dismissed {
                disableAfterDismissal()
                return
            }
            if current.activityState == .ended {
                clearTrackedActivity()
                logger.notice("Tracked activity ended; keeping monitoring enabled")
            } else if Activity<AgentActivityAttributes>.activities.contains(where: { $0.id == current.id }) {
                registryMisses = 0
            } else if now().timeIntervalSince(lastRequest) >= 5 {
                registryMisses += 1
                if registryMisses == 1 { logger.notice("Tracked activity is absent from the system registry; awaiting confirmation") }
                if registryMisses >= 2 {
                    clearTrackedActivity()
                    logger.notice("Recovering an activity missing from the system registry")
                    await current.end(nil, dismissalPolicy: .immediate)
                    guard generation == updateGeneration, isEnabled else { return }
                }
            }
        }
        guard state.connected, state.total > 0 else {
            await hide()
            return
        }
        if activity == nil, let existing = Activity<AgentActivityAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        }) {
            activity = existing
            isRunning = true
            observe(existing)
            logger.notice("Adopted an existing system activity")
        }
        if let current = activity {
            guard force || lastState != state || now().timeIntervalSince(lastUpdate) >= 30 else { return }
            await current.update(ActivityContent(state: state, staleDate: now().addingTimeInterval(90)))
            guard generation == updateGeneration, isEnabled, activity?.id == current.id else { return }
            lastState = state
            lastUpdate = now()
            message = nil
            logger.info("Updated: working=\(state.working, privacy: .public), completed=\(state.done, privacy: .public)")
            return
        }
        guard !requiresForeground || isForeground() else { return }
        guard now() >= nextRequest else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = L10n.text("Allow Live Activities for Dynamic Agents in System Settings.")
            nextRequest = now().addingTimeInterval(5)
            logger.notice("Creation deferred: system authorization is disabled")
            return
        }
        generation += 1
        let requestGeneration = generation
        lastRequest = now()
        logger.notice("Requesting activity: foreground=\(self.isForeground(), privacy: .public), eligible=\(state.total, privacy: .public)")
        do {
            for previous in Activity<AgentActivityAttributes>.activities {
                await previous.end(nil, dismissalPolicy: .immediate)
                guard requestGeneration == generation, isEnabled else { return }
            }
            activity = try Activity.request(
                attributes: AgentActivityAttributes(sessionName: L10n.text("Agent Hooks")),
                content: ActivityContent(state: state, staleDate: now().addingTimeInterval(90)),
                pushType: nil
            )
            isRunning = true
            if let activity { observe(activity) }
            lastState = state
            lastUpdate = now()
            nextRequest = .distantPast
            failedRequests = 0
            requiresForeground = false
            registryMisses = 0
            message = nil
            logger.notice("Activity request succeeded")
        } catch {
            failedRequests = min(failedRequests + 1, 5)
            let delay = min(pow(2, Double(failedRequests)), 30)
            nextRequest = now().addingTimeInterval(delay)
            isRunning = false
            let failure = error as NSError
            if let authorization = error as? ActivityAuthorizationError, authorization == .visibility {
                requiresForeground = true
                message = L10n.text("Open Dynamic Agents in the foreground to start its Live Activity. Monitoring continues in the background.")
                logger.notice("Creation deferred until foreground visibility; code=\(failure.code, privacy: .public)")
            } else {
                message = error.localizedDescription
                logger.error("Activity request failed: domain=\(failure.domain, privacy: .public), code=\(failure.code, privacy: .public), retrySeconds=\(delay, privacy: .public)")
            }
        }
        #endif
    }

    #if NATIVE_LIVE_ACTIVITIES
    private func observe(_ activity: Activity<AgentActivityAttributes>) {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, !Task.isCancelled, self.activity?.id == activity.id else { return }
                if state == .dismissed {
                    disableAfterDismissal()
                    return
                }
                if state == .ended {
                    clearTrackedActivity()
                    nextRequest = now().addingTimeInterval(2)
                    logger.notice("System activity ended; enabled preference preserved for recovery")
                    return
                }
            }
        }
    }

    private func disableAfterDismissal() {
        clearTrackedActivity()
        isEnabled = false
        UserDefaults.standard.set(false, forKey: "liveActivityEnabled")
        logger.notice("Activity dismissed; automatic creation disabled")
    }

    private func clearTrackedActivity() {
        stateTask?.cancel()
        stateTask = nil
        activity = nil
        isRunning = false
        registryMisses = 0
        lastState = nil
    }
    #endif

    private func hide() async {
        generation += 1
        stateTask?.cancel()
        stateTask = nil
        registryMisses = 0
        lastState = nil
        nextRequest = .distantPast
        failedRequests = 0
        requiresForeground = false
        message = nil
        #if NATIVE_LIVE_ACTIVITIES
        let previous = activity
        activity = nil
        isRunning = false
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
