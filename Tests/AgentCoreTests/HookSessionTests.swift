import Foundation
import Testing
@testable import AgentCore

private func session(_ index: Int = 1, status: AgentStatus = .working, completedAt: Date? = nil, available: Bool = true, title: String = "Example") -> Agent {
    Agent(hookID: String(format: "%064x", index), kind: "pi", title: title, project: "Example", status: status,
          completedAt: completedAt, hostBundleID: available ? "example.host" : nil, isSessionAvailable: available)
}

@Test func hookSessionsKeepIdentityWhenPresentationChanges() {
    let first = session(title: "Before")
    let renamed = session(title: "After")
    #expect(first.id == renamed.id)
    #expect(first.eventID == renamed.eventID)
    #expect(first.id == first.withStatus(.done).id)
    #expect(first.id.hasPrefix("hook:"))
}

@Test func runningPrecedesCompletedAndIdle() {
    #expect(AgentStatus.allCases.sorted { $0.priority < $1.priority } == [.working, .done, .idle, .unknown])
    let state = AgentActivityState(agents: [session(1, status: .idle), session(2, status: .done), session(3), session(4)])
    #expect(state.items.map(\.status) == [.working, .working, .done])
    #expect(state.status == .working)
    #expect(state.headline == L10n.format("agent.running", Int64(2)))
}

@Test func legacyWaitingPayloadsBecomeRunningWithoutASeparateCounter() throws {
    #expect(AgentStatus(serverValue: "blocked") == .working)
    #expect(try JSONDecoder().decode(AgentStatus.self, from: Data("\"blocked\"".utf8)) == .working)
    let object: [String: Any] = ["working": 0, "blocked": 1, "done": 0, "total": 1, "connected": true,
                               "languageIdentifier": "en", "items": [["id": "hook:" + String(repeating: "a", count: 40),
                                   "title": "Example", "kind": "codex", "project": "Example", "status": "blocked"]]]
    let state = try JSONDecoder().decode(AgentActivityState.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(state.working == 1 && state.status == .working && state.prominentCount == 1)
    #expect(state.items.first?.status == .working && state.compactLabels() == ["1 Work"])
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    #expect(encoded["blocked"] == nil)
    #expect(!String(decoding: try JSONEncoder().encode(state), as: UTF8.self).contains("blocked"))
}

@Test func reportedCompletionExpiresWithoutResetOnReadOrRestart() {
    let start = Date(timeIntervalSince1970: 1000)
    let done = session(status: .done, completedAt: start)
    for elapsed in [0.0, 300, 599] {
        let feed = AgentActivityFeed()
        #expect(feed.agents(from: [done], at: start.addingTimeInterval(elapsed)).first?.status == .done)
        #expect(feed.dashboardAgents(from: [done], at: start.addingTimeInterval(elapsed)).first?.status == .done)
    }
    #expect(AgentActivityFeed().agents(from: [done], at: start.addingTimeInterval(600)).isEmpty)
    #expect(AgentActivityFeed().dashboardAgents(from: [done], at: start.addingTimeInterval(600)).first?.status == .idle)
}

@Test func viewingAndClosingKeepTheOriginalCompletionReminder() throws {
    let now = Date(timeIntervalSince1970: 1100)
    let feed = AgentActivityFeed()
    let host = HostApplication(pid: 50, bundleID: "example.host", name: "Example", path: "/Applications/Example.app")
    for status in ["idle", "ended"] {
        let event = try JSONDecoder().decode(DesktopHookEvent.self, from: JSONSerialization.data(withJSONObject: [
            "id": String(repeating: "a", count: 64), "source": "claude", "status": status, "sequence": 2,
            "timestamp": 1100, "completedAt": 1000, "project": "Example", "ancestorPIDs": [50]
        ]))
        let agent = try #require(event.agent(applications: [host], now: now))
        #expect(feed.dashboardAgents(from: [agent], at: now).first?.status == .done)
        #expect(feed.agents(from: [agent], at: now).first?.status == .done)
        let expired = feed.dashboardAgents(from: [agent], at: Date(timeIntervalSince1970: 1600))
        if status == "idle" { #expect(expired.first?.status == .idle) }
        else { #expect(expired.isEmpty && !agent.isSessionAvailable) }
    }
}

@Test func retentionCanBeChangedAndIsBounded() {
    let start = Date(timeIntervalSince1970: 1000)
    let done = session(status: .done, completedAt: start)
    let feed = AgentActivityFeed()
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(120), completionLifetime: 60).isEmpty)
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(120), completionLifetime: 180).count == 1)
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(60), completionLifetime: -1).isEmpty)
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(86_400), completionLifetime: .infinity).isEmpty)
}

@Test func closedSessionsRemainOnlyForARecentReportedCompletion() {
    let now = Date(timeIntervalSince1970: 1000)
    let closed = session(status: .done, completedAt: now, available: false)
    let feed = AgentActivityFeed()
    #expect(feed.dashboardAgents(from: [closed], at: now.addingTimeInterval(599)).count == 1)
    #expect(feed.dashboardAgents(from: [closed], at: now.addingTimeInterval(600)).isEmpty)
    for status in [AgentStatus.working, .idle, .unknown] {
        let unavailable = session(status: status, available: false)
        #expect(feed.dashboardAgents(from: [unavailable], at: now).isEmpty)
        #expect(feed.agents(from: [unavailable], at: now).isEmpty)
    }
}

@Test func onlyRunningAndRecentCompletionsBelongInLiveActivities() {
    let now = Date.now
    let rows = [session(1), session(2, status: AgentStatus(serverValue: "blocked")), session(3, status: .idle), session(4, status: .unknown), session(5, status: .done, completedAt: now)]
    let feed = AgentActivityFeed()
    #expect(feed.dashboardAgents(from: rows, at: now).count == 5)
    #expect(feed.agents(from: rows, at: now).map(\.status) == [.working, .working, .done])
    #expect(feed.agents(from: [session(status: .done)], at: now).isEmpty)
    #expect(feed.agents(from: [session(status: .done, completedAt: now.addingTimeInterval(1))], at: now).isEmpty)
}

@Test func payloadsBoundManySessionsAndPathologicalTitles() throws {
    let title = String(repeating: "界\u{301}\u{0000}", count: 5000)
    let rows = (1...1000).map { session($0, title: title) }
    let state = AgentActivityState(agents: rows, itemLimit: .max, languageIdentifier: "zh-Hans")
    #expect(state.total == 1000 && state.working == 1000)
    #expect(state.items.count > 3)
    #expect(try JSONEncoder().encode(state).count < 4096)
    #expect(state.compactLabels() == ["99+ 运行"])
    #expect(state.items.allSatisfy { !$0.title.contains("\u{0000}") })
    var offline = state
    offline.connected = false
    #expect(offline.status == .unknown)
    #expect(offline.compactLabels(locale: Locale(identifier: "en")) == ["Offline"])
}

@Test func hostSelectionUsesTheObservedProcessAndRejectsAReusedIdentity() throws {
    let event = try JSONDecoder().decode(DesktopHookEvent.self, from: JSONSerialization.data(withJSONObject: [
        "id": String(repeating: "a", count: 64), "source": "claude", "status": "working", "sequence": 1,
        "timestamp": 1000, "project": "Example", "ancestorPIDs": [61, 50]
    ]))
    let observed = HostApplication(pid: 50, bundleID: "example.host", name: "Example", path: "/Applications/Example.app")
    let other = HostApplication(pid: 51, bundleID: "example.host", name: "Example", path: "/Applications/Example.app")
    #expect(HostAppSelection.application(for: event, bundleID: observed.bundleID, applications: [other, observed], launchDates: [50: Date(timeIntervalSince1970: 900)]) == observed)
    #expect(HostAppSelection.application(for: event, bundleID: observed.bundleID, applications: [observed], launchDates: [50: Date(timeIntervalSince1970: 1100)]) == nil)
    #expect(HostAppSelection.application(for: event, bundleID: "other.host", applications: [observed], launchDates: [50: .distantPast]) == nil)
    #expect(HostAppSelection.application(for: event, bundleID: observed.bundleID, applications: [other], launchDates: [51: .distantPast]) == nil)
}
