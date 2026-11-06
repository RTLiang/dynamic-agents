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
            agents = snapshot.trackedAgents
            if activityFeed.observe(agents, at: .now), let data = try? JSONEncoder().encode(activityFeed) {
                UserDefaults.standard.set(data, forKey: "activityFeed")
            }
            workspaces = snapshot.workspaces
            connected = true
            connectionError = nil
            lastUpdated = .now
        } catch {
            guard !Task.isCancelled, requestClient.executable == executable, requestClient.session == session else { return }
            connected = false
            connectionError = error.localizedDescription
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
            agents = []
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
        do { try await requestClient.focus(agent.id) }
        catch { actionError = error.localizedDescription; return }
        await refreshTerminals()
        guard requestClient.executable == executable, requestClient.session == session, preferredTerminal == terminalBundleID else { return }
        do { try await terminal.activate(preferredBundleID: preferredTerminal) }
        catch { actionError = L10n.format("The herdr pane is selected. %@", error.localizedDescription) }
        await refresh()
    }
}
