import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

@Observable @MainActor
final class AgentStore {
    static let shared = AgentStore()
    private(set) var agents: [Agent] = []
    private(set) var connected = false
    private(set) var loading = true
    private(set) var lastUpdated: Date?
    var actionError: String?
    private(set) var presentsActionError = true
    var focusingID: String?
    let liveActivity = LiveActivityController()
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var suspended = false
    private let activityFeed = AgentActivityFeed()

    var state: AgentActivityState { AgentActivityState(agents: agents, connected: connected) }
    private var completionLifetime: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: "completionWindowMinutes") as? Int ?? 10
        return TimeInterval(min(max(minutes, 1), 1440) * 60)
    }
    var activityState: AgentActivityState {
        AgentActivityState(agents: activityFeed.agents(from: agents, at: .now, completionLifetime: completionLifetime), connected: connected, prioritizeRunning: true, itemLimit: .max)
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended { await self.refresh() }
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
    func setSleeping(_ value: Bool) {
        suspended = value
        if value {
            connected = false
            Task { await liveActivity.update(activityState) }
        } else { Task { await refresh() } }
    }
    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task {
            defer { self.refreshTask = nil; loading = false }
            await refreshHooks()
        }
        refreshTask = task
        await task.value
    }
    private func refreshHooks() async {
        let hookSnapshot = await Task.detached(priority: .utility) { await DesktopHooks.capture() }.value
        guard !Task.isCancelled, !suspended else { return }
        let runningApps = NSWorkspace.shared.runningApplications
        let launchDates = Dictionary(runningApps.compactMap { app in app.launchDate.map { (app.processIdentifier, $0) } }, uniquingKeysWith: { first, _ in first })
        let applications = runningApps.compactMap { app -> HostApplication? in
            guard app.activationPolicy == .regular, let bundle = app.bundleIdentifier, let url = app.bundleURL,
                  bundle != Bundle.main.bundleIdentifier else { return nil }
            return HostApplication(pid: app.processIdentifier, bundleID: bundle, name: app.localizedName ?? bundle, path: url.path)
        }
        let now = Date.now
        let observed = hookSnapshot.events.compactMap { event in
            let hosts = applications.filter { launchDates[$0.pid].map { $0.timeIntervalSince1970 <= event.timestamp } ?? false }
            return event.agent(applications: hosts, now: now, processes: hookSnapshot.processes)
        }
        agents = activityFeed.dashboardAgents(from: observed, at: now, completionLifetime: completionLifetime)
        connected = true
        lastUpdated = now
        await liveActivity.update(activityState)
    }

    func focus(_ agent: Agent, presentsError: Bool = true) async {
        guard focusingID == nil else { return }
        presentsActionError = presentsError
        focusingID = agent.id
        actionError = nil
        defer { focusingID = nil }
        let snapshot = await Task.detached { await DesktopHooks.capture() }.value
        let running = NSWorkspace.shared.runningApplications
        let applications = running.compactMap { app -> HostApplication? in
            guard app.activationPolicy == .regular, let bundle = app.bundleIdentifier, let path = app.bundleURL?.path,
                  bundle != Bundle.main.bundleIdentifier else { return nil }
            return HostApplication(pid: app.processIdentifier, bundleID: bundle, name: app.localizedName ?? bundle, path: path)
        }
        let launchDates = Dictionary(running.compactMap { app in app.launchDate.map { (app.processIdentifier, $0) } }, uniquingKeysWith: { first, _ in first })
        guard let event = snapshot.events.first(where: { $0.id == agent.eventID }),
              let bundle = agent.hostBundleID,
              let host = HostAppSelection.application(for: event, bundleID: bundle, applications: applications, launchDates: launchDates),
              event.agent(applications: [host], now: .now, processes: snapshot.processes)?.hostBundleID == bundle,
              let app = NSRunningApplication(processIdentifier: host.pid), !app.isTerminated else {
            actionError = L10n.text("The hook session's host app is unavailable.")
            return
        }
        NSApp.yieldActivation(to: app)
        app.unhide()
        if !app.activate(options: []) { actionError = L10n.text("Unable to open the agent's desktop client.") }
    }
}
