import Foundation
import Testing
@testable import AgentCore

private func agent(_ status: String, sequence: Int? = nil) throws -> Agent {
    var value: [String: Any] = ["pane_id": "w1:p1", "workspace_id": "w1", "terminal_id": "term1", "agent": "pi", "agent_status": status]
    if let sequence { value["completion_seq"] = sequence }
    return try JSONDecoder().decode(Agent.self, from: JSONSerialization.data(withJSONObject: value))
}

@Test func configurableDurationAppliesAtExactBoundaryAndCanBeExtendedAfterExpiry() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 10_000)
    feed.observe([try agent("working")], at: start)
    let done = try agent("done", sequence: 123)
    feed.observe([done], at: start.addingTimeInterval(1))
    let expired = start.addingTimeInterval(121)
    feed.observe([done], at: expired)
    #expect(feed.agents(from: [done], at: expired, completionLifetime: 120).isEmpty)
    #expect(feed.agents(from: [done], at: expired, completionLifetime: 180).count == 1)
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(181), completionLifetime: 180).isEmpty)
    let restored = try JSONDecoder().decode(AgentActivityFeed.self, from: JSONEncoder().encode(feed))
    #expect(restored.agents(from: [done], at: expired, completionLifetime: 180).count == 1)
}

@Test func durationIsBoundedAndRunningAgentsAreUnaffected() throws {
    var feed = AgentActivityFeed()
    let start = Date(timeIntervalSince1970: 10_000)
    let running = try agent("working")
    feed.observe([running], at: start)
    let done = try agent("done", sequence: 124)
    feed.observe([done], at: start.addingTimeInterval(1))
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(60), completionLifetime: 0).count == 1)
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(61), completionLifetime: 0).isEmpty)
    #expect(feed.agents(from: [done], at: start.addingTimeInterval(86_401), completionLifetime: 900_000).isEmpty)
    #expect(feed.agents(from: [running], at: start.addingTimeInterval(90_000), completionLifetime: 60).count == 1)
}

@Test func localizedMinutesHaveCorrectGrammar() {
    #expect(L10n.format("duration.minutes", Int64(1), locale: Locale(identifier: "en")) == "1 minute")
    #expect(L10n.format("duration.minutes", Int64(10), locale: Locale(identifier: "en")) == "10 minutes")
    #expect(L10n.format("duration.minutes", Int64(10), locale: Locale(identifier: "zh-Hans")) == "10 分钟")
}
