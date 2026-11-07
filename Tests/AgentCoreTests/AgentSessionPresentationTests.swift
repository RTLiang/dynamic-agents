import Foundation
import Testing
@testable import AgentCore

private func openSession(_ status: AgentStatus, sequence: UInt64? = nil, id: String = "w1:p1") throws -> Agent {
    var fields: [String: Any] = ["pane_id": id, "workspace_id": "w1", "agent": "codex", "agent_status": status.rawValue]
    if let sequence { fields["completion_seq"] = sequence }
    return try JSONDecoder().decode(Agent.self, from: JSONSerialization.data(withJSONObject: fields))
}

private func desktopSession(_ status: AgentStatus, at date: Date, available: Bool) -> Agent {
    Agent(hookID: String(repeating: "a", count: 64), kind: "codex", title: "Coding session", project: "Example",
          status: status, sequence: 1, completedAt: status == .done ? date : nil,
          hostBundleID: available ? "example.client" : nil, isSessionAvailable: available)
}

@Test func sessionOrderAndHeadlineKeepRunningAheadOfCompletedAndIdle() throws {
    #expect(AgentStatus.allCases.sorted { $0.priority < $1.priority } == [.working, .blocked, .done, .idle, .unknown])
    let sessions = try [AgentStatus.idle, .done, .working, .blocked].enumerated().map { try openSession($0.element, id: "w1:p\($0.offset)") }
    let state = AgentActivityState(agents: sessions, workspaces: [])
    #expect(state.items.map(\.status) == [.working, .blocked, .done])
    #expect(state.status == .working)
    #expect(state.headline == L10n.format("agent.running", Int64(1)))
}

@Test func aViewedCompletionStaysCompletedUntilTheReminderExpires() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var feed = AgentActivityFeed()
    feed.observe([try openSession(.working)], at: start)
    let done = try openSession(.done, sequence: 2)
    feed.observe([done], at: start.addingTimeInterval(1))
    let viewed = try openSession(.idle, sequence: 2)
    feed.observe([viewed], at: start.addingTimeInterval(2))
    #expect(feed.dashboardAgents(from: [viewed], at: start.addingTimeInterval(600)).first?.status == .done)
    #expect(feed.dashboardAgents(from: [viewed], at: start.addingTimeInterval(601)).first?.status == .idle)
    #expect(feed.agents(from: [viewed], at: start.addingTimeInterval(601)).isEmpty)
}

@Test func oldUnobservedCompletionsAreIdleRatherThanFreshResults() throws {
    let now = Date(timeIntervalSince1970: 1000)
    let done = try openSession(.done, sequence: 100)
    var feed = AgentActivityFeed()
    feed.observe([done], at: now)
    #expect(feed.dashboardAgents(from: [done], at: now).first?.status == .idle)
    #expect(feed.agents(from: [done], at: now).isEmpty)
}

@Test func closedDesktopSessionsRemainOnlyForTheirActualCompletionReminder() {
    let now = Date(timeIntervalSince1970: 1000)
    let done = desktopSession(.done, at: now, available: false)
    var feed = AgentActivityFeed()
    feed.observe([done], at: now)
    #expect(feed.dashboardAgents(from: [done], at: now.addingTimeInterval(599)).first?.status == .done)
    #expect(feed.dashboardAgents(from: [done], at: now.addingTimeInterval(600)).isEmpty)
    let idle = desktopSession(.idle, at: now, available: false)
    let unknown = desktopSession(.unknown, at: now, available: false)
    #expect(feed.dashboardAgents(from: [idle, unknown], at: now).isEmpty)
}

@Test func anAvailableDesktopSessionBecomesIdleAfterCompletionWithoutRestartingItsClock() {
    let now = Date(timeIntervalSince1970: 1000)
    let done = desktopSession(.done, at: now, available: true)
    var feed = AgentActivityFeed()
    feed.observe([done], at: now)
    #expect(feed.dashboardAgents(from: [done], at: now.addingTimeInterval(600)).first?.status == .idle)
    #expect(feed.dashboardAgents(from: [done], at: now.addingTimeInterval(600), completionLifetime: 900).first?.status == .done)
    #expect(feed.dashboardAgents(from: [done], at: now.addingTimeInterval(900), completionLifetime: 900).first?.status == .idle)
}

@Test func interruptionIsIdleAndDoesNotCreateACompletionReminder() throws {
    let now = Date(timeIntervalSince1970: 1000)
    var feed = AgentActivityFeed()
    feed.observe([try openSession(.working)], at: now)
    let interrupted = try openSession(.idle)
    feed.observe([interrupted], at: now.addingTimeInterval(1))
    #expect(feed.dashboardAgents(from: [interrupted], at: now.addingTimeInterval(2)).first?.status == .idle)
    #expect(feed.agents(from: [interrupted], at: now.addingTimeInterval(2)).isEmpty)
}
