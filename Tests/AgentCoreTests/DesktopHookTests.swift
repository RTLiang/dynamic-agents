import Foundation
import Testing
@testable import AgentCore

private func hookEvent(status: String, source: String = "codex", age: TimeInterval = 0, ancestors: [Int32] = [51, 50]) throws -> DesktopHookEvent {
    let data: [String: Any] = ["id": String(repeating: "a", count: 64), "source": source, "status": status,
                               "sequence": 1234, "timestamp": Date.now.timeIntervalSince1970 - age,
                               "project": "Example", "ancestorPIDs": ancestors]
    return try JSONDecoder().decode(DesktopHookEvent.self, from: JSONSerialization.data(withJSONObject: data))
}

@Test func desktopEventUsesObservedHostAndNeverTreatsOpenAppAsTaskActivity() throws {
    let app = TerminalApplication(pid: 50, bundleID: "example.desktop", name: "Example Desktop", path: "/Applications/Example.app")
    let event = try hookEvent(status: "working")
    let agent = try #require(event.agent(applications: [app], now: .now))
    #expect(agent.isHookSession && agent.status == .working)
    #expect(agent.hostBundleID == "example.desktop")
    #expect(agent.id.hasPrefix("hook:") && agent.kind == "codex")
    #expect(event.agent(applications: [], now: .now)?.status == .unknown)
    #expect(try hookEvent(status: "idle").agent(applications: [app], now: .now)?.status == .idle)
}

@Test func desktopReportedCompletionTimeSurvivesFirstReadAndDurationChanges() throws {
    let done = try #require(hookEvent(status: "done", age: 300).agent(applications: [], now: .now))
    var feed = AgentActivityFeed()
    feed.observe([done], at: .now)
    #expect(feed.agents(from: [done], at: .now, completionLifetime: 600).count == 1)
    #expect(feed.agents(from: [done], at: .now, completionLifetime: 120).isEmpty)
    #expect(done.hookCompletedAt != nil && done.completionSequence == 1234)
}

@Test func desktopEndedExpiredFutureAndUnknownSourcesDoNotBecomeLiveSessions() throws {
    #expect(try hookEvent(status: "ended").agent(applications: [], now: .now) == nil)
    #expect(try hookEvent(status: "done", age: 90_000).agent(applications: [], now: .now) == nil)
    #expect(try hookEvent(status: "done", age: -100).agent(applications: [], now: .now) == nil)
    #expect(try hookEvent(status: "working", source: "unrelated-chat").agent(applications: [], now: .now) == nil)
}

@Test func desktopEventsDoNotChangeHerdrAgentIdentityOrDecodeDefaults() throws {
    let data = Data("{\"pane_id\":\"w1:p1\",\"workspace_id\":\"w1\",\"agent\":\"codex\",\"agent_status\":\"working\"}".utf8)
    let agent = try JSONDecoder().decode(Agent.self, from: data)
    #expect(!agent.isHookSession && agent.hostBundleID == nil && agent.hookCompletedAt == nil)
    #expect(agent.withStatus(.done).id == "w1:p1")
    let event = try #require(hookEvent(status: "done").agent(applications: [], now: .now))
    let payload = AgentActivityState(agents: [event], workspaces: [])
    #expect(payload.items.first?.id == event.id)
    #expect(payload.items.first?.status == .done)
    #expect(try JSONEncoder().encode(payload).count < 4096)
}

@Test func desktopCollectorHonorsRemovedSourceAndIgnoresMalformedEvents() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("desktop-hook-" + UUID().uuidString, isDirectory: true)
    let events = root.appendingPathComponent("events", isDirectory: true)
    try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
    defer {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["trash", root.path]
        try? process.run()
        process.waitUntilExit()
    }
    let value: [String: Any] = ["id": String(repeating: "a", count: 64), "source": "codex", "status": "working",
                               "sequence": 42, "timestamp": Date.now.timeIntervalSince1970, "project": "Example", "ancestorPIDs": [12]]
    try JSONSerialization.data(withJSONObject: value).write(to: events.appendingPathComponent("event.json"))
    try Data("invalid JSON".utf8).write(to: events.appendingPathComponent("bad.json"))
    #expect(DesktopHooks.readEvents(in: root).count == 1)
    try Data("{\"codex\":false}".utf8).write(to: root.appendingPathComponent("sources.json"))
    #expect(DesktopHooks.readEvents(in: root).isEmpty)
}
