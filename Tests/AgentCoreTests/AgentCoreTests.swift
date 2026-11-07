import Foundation
import Testing
@testable import AgentCore

private func response(_ agents: String) -> Data {
    Data("""
    {"id":"test","result":{"snapshot":{"agents":\(agents),"workspaces":[{"workspace_id":"w1","label":"Demo"}],"version":"0.9.5"},"type":"session_snapshot"}}
    """.utf8)
}

@Test func decodesHerdrEnvelopeAndSortsRunningFirst() throws {
    let snapshot = try Snapshot.decode(response("""
    [
      {"pane_id":"w1:p1","workspace_id":"w1","agent":"pi","agent_status":"working","terminal_title_stripped":"Build","cwd":"/tmp/demo"},
      {"pane_id":"w1:p2","workspace_id":"w1","agent":"codex","agent_status":"blocked"},
      {"pane_id":"w1:p3","workspace_id":"w1","agent":null,"agent_status":"idle"},
      {"pane_id":"w1:p4","workspace_id":"w1","agent":"claude","agent_status":"done"}
    ]
    """))
    #expect(snapshot.trackedAgents.map(\.id) == ["w1:p1", "w1:p2", "w1:p4"])
    let state = AgentActivityState(agents: snapshot.trackedAgents, workspaces: snapshot.workspaces)
    #expect(state.blocked == 1 && state.working == 1 && state.done == 1 && state.total == 3)
    #expect(state.status == .working)
    #expect(state.items.first?.project == "Demo")
}

@Test func unknownStatesRemainVisibleAndMissingTitlesFallBack() throws {
    let snapshot = try Snapshot.decode(response("""
    [{"pane_id":"w1:p1","workspace_id":"w1","agent":"future-agent","agent_status":"reviewing","terminal_title_stripped":"","terminal_title":"Review"}]
    """))
    #expect(snapshot.trackedAgents.first?.status == .unknown)
    #expect(snapshot.trackedAgents.first?.title == "Review")
}

@Test func rejectsErrorEnvelopeAndMalformedSnapshot() {
    #expect(throws: (any Error).self) { try Snapshot.decode(Data("{\"error\":{\"message\":\"offline\"}}".utf8)) }
    #expect(throws: (any Error).self) { try Snapshot.decode(Data("{\"result\":{}}".utf8)) }
    #expect(throws: (any Error).self) { try Snapshot.decode(response("[{\"agent\":\"pi\"}]")) }
}

@Test func activityPayloadIsBoundedWithMultibyteTitles() throws {
    let agents: [[String: String]] = (0..<100).map { index in
        ["pane_id": "w1:p\(index)", "workspace_id": "w1", "agent": "pi", "agent_status": "working", "terminal_title": String(repeating: "🚀", count: 1000)]
    }
    let data = try JSONSerialization.data(withJSONObject: agents)
    let snapshot = try Snapshot.decode(response(String(decoding: data, as: UTF8.self)))
    let state = AgentActivityState(agents: snapshot.trackedAgents, workspaces: snapshot.workspaces)
    #expect(state.total == 100)
    #expect(state.items.count == 3)
    #expect(try JSONEncoder().encode(state).count < 4096)
    let pathologicalTitle = "e" + String(repeating: "\u{0301}", count: 10000)
    let pathological = try Snapshot.decode(response("""
    [{"pane_id":"w1:p1","workspace_id":"w1","agent":"pi","terminal_title":"\(pathologicalTitle)"}]
    """))
    let bounded = AgentActivityState(agents: pathological.trackedAgents, workspaces: pathological.workspaces)
    #expect(try JSONEncoder().encode(bounded).count < 4096)
    var disconnected = state
    disconnected.connected = false
    #expect(disconnected.status == .unknown)
    #expect(disconnected.headline == L10n.text("herdr connection lost"))
}

@Test func commandRunnerPreservesArgumentsWithoutShellExpansion() async throws {
    let output = try await CommandRunner.run(executable: "/usr/bin/printf", arguments: ["%s", "$(whoami); value with spaces"])
    #expect(String(decoding: output, as: UTF8.self) == "$(whoami); value with spaces")
}

@Test func commandRunnerReportsMissingBinaryAndNonzeroExit() async {
    await #expect(throws: (any Error).self) {
        try await CommandRunner.run(executable: "/no-such-herdr", arguments: [])
    }
    await #expect(throws: (any Error).self) {
        try await CommandRunner.run(executable: "/usr/bin/false", arguments: [])
    }
}

@Test func commandRunnerTimesOut() async {
    let start = Date.now
    await #expect(throws: (any Error).self) {
        try await CommandRunner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.1)
    }
    #expect(Date.now.timeIntervalSince(start) < 2)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["HERDR_LIVE_TEST"] == "1"))
func readsRealHerdrSnapshot() async throws {
    let snapshot = try await HerdrClient().snapshot()
    #expect(!snapshot.version.isEmpty)
    print("herdr \(snapshot.version): \(snapshot.trackedAgents.count) agents / \(snapshot.workspaces.count) workspaces")
}
