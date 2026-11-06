import Foundation
import Testing
@testable import AgentCore

private func feedAgent(_ status: String, sequence: Int? = nil, terminal: String = "term1", id: String = "w1:p1") throws -> Agent {
    var fields: [String: Any] = ["pane_id": id, "terminal_id": terminal, "workspace_id": "w1", "agent": "codex", "agent_status": status]
    if let sequence { fields["completion_seq"] = sequence }
    return try JSONDecoder().decode(Agent.self, from: JSONSerialization.data(withJSONObject: fields))
}

@Test func islandExcludesWaitingIdleUnknownAndUnverifiableOldCompletions() throws {
    let agents = try [feedAgent("working", id: "working"), feedAgent("blocked", id: "blocked"),
                      feedAgent("idle", id: "idle"), feedAgent("done", sequence: 7, id: "old-done")]
    var feed = AgentActivityFeed()
    let now = Date(timeIntervalSince1970: 1000)
    feed.observe(agents, at: now)
    #expect(feed.agents(from: agents, at: now).map(\.id) == ["working"])
}

@Test func completionSurvivesBeingViewedButExpiresAtExactlyTenMinutes() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 1000)
    feed.observe([try feedAgent("working")], at: start)
    let completed = try feedAgent("done", sequence: 8)
    feed.observe([completed], at: start.addingTimeInterval(1))
    let viewed = try feedAgent("idle", sequence: 8)
    feed.observe([viewed], at: start.addingTimeInterval(2))
    feed.observe([completed], at: start.addingTimeInterval(3))
    #expect(feed.agents(from: [viewed], at: start.addingTimeInterval(600)).first?.status == .done)
    #expect(feed.agents(from: [viewed], at: start.addingTimeInterval(601)).isEmpty)
    feed.observe([viewed], at: start.addingTimeInterval(602))
    #expect(feed.agents(from: [viewed], at: start.addingTimeInterval(602)).isEmpty)
}

@Test func focusedCompletionIsDetectedEvenWhenUpstreamAlreadySaysIdle() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 1000)
    feed.observe([try feedAgent("working")], at: start)
    let completed = try feedAgent("idle", sequence: 9)
    feed.observe([completed], at: start.addingTimeInterval(1))
    #expect(feed.agents(from: [completed], at: start.addingTimeInterval(2)).first?.status == .done)
    let resumed = try feedAgent("working")
    feed.observe([resumed], at: start.addingTimeInterval(3))
    #expect(feed.agents(from: [resumed], at: start.addingTimeInterval(3)).first?.status == .working)
    let waiting = try feedAgent("blocked")
    feed.observe([waiting], at: start.addingTimeInterval(4))
    #expect(feed.agents(from: [waiting], at: start.addingTimeInterval(4)).isEmpty)
}

@Test func sleepAndTerminalReplacementDoNotManufactureRecentCompletions() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 1000)
    feed.observe([try feedAgent("working")], at: start)
    let unknownTime = try feedAgent("done", sequence: 10)
    feed.observe([unknownTime], at: start.addingTimeInterval(700))
    #expect(feed.agents(from: [unknownTime], at: start.addingTimeInterval(700)).isEmpty)
    let replaced = try feedAgent("done", sequence: 11, terminal: "term2")
    feed.observe([replaced], at: start.addingTimeInterval(701))
    #expect(feed.agents(from: [replaced], at: start.addingTimeInterval(701)).isEmpty)
}

@Test func restartPreservesKnownCompletionTimeWithoutRestartingItsClock() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 1000)
    feed.observe([try feedAgent("working")], at: start)
    let completed = try feedAgent("done", sequence: 12)
    feed.observe([completed], at: start.addingTimeInterval(1))
    var restored = try JSONDecoder().decode(AgentActivityFeed.self, from: JSONEncoder().encode(feed))
    restored.observe([completed], at: start.addingTimeInterval(500))
    #expect(restored.agents(from: [completed], at: start.addingTimeInterval(500)).count == 1)
    #expect(restored.agents(from: [completed], at: start.addingTimeInterval(601)).isEmpty)
}

@Test func activityShowsRunningBeforeRecentCompletionsAndBecomesEmptyWhenAllExpire() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 1000)
    let running = try feedAgent("working", id: "running")
    let busy = try feedAgent("working", id: "completed")
    feed.observe([running, busy], at: start)
    let done = try feedAgent("done", sequence: 13, id: "completed")
    feed.observe([running, done], at: start.addingTimeInterval(1))
    let state = AgentActivityState(agents: feed.agents(from: [running, done], at: start.addingTimeInterval(2)), workspaces: [], prioritizeRunning: true)
    #expect(state.total == 2 && state.working == 1 && state.done == 1 && state.blocked == 0)
    #expect(state.items.first?.id == "running")
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(601)).isEmpty)
    feed.observe([], at: start.addingTimeInterval(602))
    #expect(feed.agents(from: [], at: start.addingTimeInterval(602)).isEmpty)
}

@Test func expandedActivityIncludesEverySessionBeyondThreeAndBoundsLargePayloads() throws {
    let agents = try (0..<8).map { try feedAgent("working", id: "w1:p\($0)") }
    let state = AgentActivityState(agents: agents, workspaces: [], prioritizeRunning: true, itemLimit: .max)
    #expect(state.items.count == 8 && state.total == 8)
    #expect(Set(state.items.map(\.id)) == Set(agents.map(\.id)))
    let many = try (0..<100).map { try feedAgent("working", id: "w1:p\($0)") }
    let bounded = AgentActivityState(agents: many, workspaces: [], prioritizeRunning: true, itemLimit: .max)
    #expect(bounded.total == 100 && bounded.items.count > 3 && bounded.items.count < 100)
    #expect(try JSONEncoder().encode(bounded).count < 4096)
}
