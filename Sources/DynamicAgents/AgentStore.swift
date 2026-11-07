import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

@Observable @MainActor
final class AgentStore {
    static let shared = AgentStore()
    private(set) var agents: [Agent] = []
    private(set) var workspaces: [Workspace] = []
    private(set) var connected = false
    private(set) var loading = true
    private(set) var lastUpdated: Date?
    private(set) var connectionError: String?
    var actionError: String?
    var focusingID: String?
    let liveActivity = LiveActivityController()
    let terminal = TerminalController()
    private var lastTerminalScan = Date.distantPast
    var executable: String { didSet { UserDefaults.standard.set(executable, forKey: "herdrExecutable") } }
    var session: String { didSet { UserDefaults.standard.set(session, forKey: "herdrSession") } }
    var terminalBundleID: String { didSet { UserDefaults.standard.set(terminalBundleID, forKey: "terminalBundleID") } }
    private var pollTask: Task<Void, Never>?
    private var refreshing = false
    private var suspended = false
    private var activityFeed = AgentActivityFeed()
    private var herdrAgents: [Agent] = []
    private var herdrWorkspaces: [Workspace] = []
    private(set) var herdrConnected = false

    init() {
        let defaults = UserDefaults.standard
        executable = defaults.string(forKey: "herdrExecutable") ?? HerdrClient.defaultExecutable
        session = defaults.string(forKey: "herdrSession") ?? ""
        terminalBundleID = defaults.string(forKey: "terminalBundleID") ?? ""
        if let data = defaults.data(forKey: "activityFeed"), let feed = try? JSONDecoder().decode(AgentActivityFeed.self, from: data) {
            activityFeed = feed
        }
    }
    var state: AgentActivityState { AgentActivityState(agents: agents, workspaces: workspaces, connected: connected) }
    var activityState: AgentActivityState {
        let storedMinutes = UserDefaults.standard.object(forKey: "completionWindowMinutes") as? Int ?? 10
        let minutes = min(max(storedMinutes, 1), 1440)
        return AgentActivityState(agents: activityFeed.agents(from: agents, at: .now, completionLifetime: TimeInterval(minutes * 60)), workspaces: workspaces, connected: connected, prioritizeRunning: true, itemLimit: .max)
    }
    var client: HerdrClient { HerdrClient(executable: executable, session: session) }
    func workspaceName(_ id: String) -> String { workspaces.first { $0.id == id }?.label ?? id }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.suspended {
                    await self.refresh()
                    if Date.now.timeIntervalSince(self.lastTerminalScan) >= 15 { await self.refreshTerminals() }
                }
                do { try await Task.sleep(for: .seconds(self.connected ? 1 : 3)) }
                catch { return }
            }
        }
    }
    func setSleeping(_ value: Bool) { suspended = value }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let requestClient = client
        defer { refreshing = false; loading = false }
        do {
            let snapshot = try await requestClient.snapshot()
            guard !Task.isCancelled, requestClient.executable == executable, requestClient.session == session else { return }
            herdrAgents = snapshot.trackedAgents.map { $0.scoped(to: requestClient.session) }
            herdrWorkspaces = snapshot.workspaces
            herdrConnected = true
            connectionError = nil
            lastUpdated = .now
        } catch {
            guard !Task.isCancelled, requestClient.executable == executable, requestClient.session == session else { return }
            herdrConnected = false
            connectionError = error.localizedDescription
        }
        let runningApps = NSWorkspace.shared.runningApplications
        let launchDates = Dictionary(runningApps.compactMap { app in app.launchDate.map { (app.processIdentifier, $0) } }, uniquingKeysWith: { first, _ in first })
        let applications = runningApps.compactMap { app -> TerminalApplication? in
            guard app.activationPolicy == .regular, let bundle = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            return TerminalApplication(pid: app.processIdentifier, bundleID: bundle, name: app.localizedName ?? bundle, path: url.path)
        }
        let hookSnapshot = await Task.detached(priority: .utility) { await DesktopHooks.capture() }.value
        let desktopAgents = hookSnapshot.events.compactMap { event in
            let hosts = applications.filter { launchDates[$0.pid].map { $0.timeIntervalSince1970 <= event.timestamp } ?? false }
            return event.agent(applications: hosts, now: .now, processes: hookSnapshot.processes)
        }
        agents = (herdrConnected ? herdrAgents : herdrAgents.map { $0.withStatus(.unknown) }) + desktopAgents
        let desktopWorkspaces = Dictionary(desktopAgents.map { ($0.workspaceID, $0.projectName ?? $0.kindName) }, uniquingKeysWith: { first, _ in first })
        workspaces = herdrWorkspaces + desktopWorkspaces.map { Workspace(id: $0.key, label: $0.value) }
        connected = herdrConnected || !desktopAgents.isEmpty
        if activityFeed.observe(agents, at: .now), let data = try? JSONEncoder().encode(activityFeed) {
            UserDefaults.standard.set(data, forKey: "activityFeed")
        }
        await liveActivity.update(activityState, session: session)
    }
    func refreshTerminals() async {
        lastTerminalScan = .now
        await terminal.refresh(executable: executable, session: session, preferredBundleID: terminalBundleID)
    }
    func applySettings(executable: String, session: String, terminalBundleID: String) async {
        let connectionChanged = self.executable != executable || self.session != session
        self.executable = executable
        self.session = session
        self.terminalBundleID = terminalBundleID
        if connectionChanged {
            await liveActivity.stop()
            terminal.preferredClientID = ""
            agents = []
            herdrAgents = []
            herdrWorkspaces = []
            herdrConnected = false
            activityFeed = AgentActivityFeed()
            UserDefaults.standard.removeObject(forKey: "activityFeed")
            workspaces = []
            connected = false
            lastUpdated = nil
            await refresh()
        }
        if !connectionChanged { await liveActivity.update(activityState, session: session) }
        await refreshTerminals()
    }
    func openTerminal() async {
        actionError = nil
        await refreshTerminals()
        do { try await terminal.activate(preferredBundleID: terminalBundleID) }
        catch { actionError = error.localizedDescription }
    }
    func focus(_ agent: Agent) async {
        guard connected, focusingID == nil else { return }
        focusingID = agent.id
        actionError = nil
        let requestClient = client
        let preferredTerminal = terminalBundleID
        defer { focusingID = nil }
        if agent.isHookSession {
            let hookSnapshot = await Task.detached { await DesktopHooks.capture() }.value
            guard let event = hookSnapshot.events.first(where: { "hook:" + $0.id == agent.terminalID }),
                  let bundle = agent.hostBundleID,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(where: {
                      event.ancestorPIDs.contains($0.processIdentifier) && ($0.launchDate.map { $0.timeIntervalSince1970 <= event.timestamp } ?? false)
                  }) else {
                actionError = L10n.text("The hook session's host app is unavailable.")
                return
            }
            let observedApp = TerminalApplication(pid: app.processIdentifier, bundleID: bundle, name: app.localizedName ?? bundle, path: app.bundleURL?.path ?? "")
            guard event.agent(applications: [observedApp], now: .now, processes: hookSnapshot.processes)?.hostBundleID == bundle else {
                actionError = L10n.text("The hook session's host app is unavailable.")
                return
            }
            if TerminalController.isTerminal(bundle) {
                do { try await terminal.activateHook(event, host: app) }
                catch { actionError = error.localizedDescription }
            } else {
                NSApp.yieldActivation(to: app)
                app.unhide()
                if !app.activate(options: []) { actionError = L10n.text("Unable to open the agent's desktop client.") }
            }
            return
        }
        guard herdrConnected else { actionError = connectionError; return }
        guard agent.herdrSession == (session.isEmpty ? "default" : session), agents.contains(where: { $0.id == agent.id }) else {
            actionError = L10n.text("This agent belongs to a different herdr session. Refresh the activity and try again.")
            return
        }
        await refreshTerminals()
        guard requestClient.executable == executable, requestClient.session == session, preferredTerminal == terminalBundleID else { return }
        do {
            let target = try terminal.prepareFocus(paneID: agent.paneID, preferredBundleID: preferredTerminal)
            guard requestClient.executable == executable, requestClient.session == session else { return }
            try terminal.present(target, paneID: agent.paneID, executable: requestClient.executable, session: requestClient.session)
        } catch { actionError = error.localizedDescription }
        await refresh()
    }
}
