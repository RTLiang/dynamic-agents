import Foundation
import Testing
@testable import AgentCore

private let herdr095Kinds = [
    "pi", "claude", "codex", "gemini", "cursor", "devin", "agy", "cline",
    "omp", "mastracode", "opencode", "copilot", "kimi", "kiro", "droid", "amp",
    "grok", "hermes", "kilo", "qodercli", "qwen", "letta", "maki", "muse"
]

private func snapshot(_ agents: [[String: Any]]) throws -> Snapshot {
    let data = try JSONSerialization.data(withJSONObject: ["result": ["snapshot": [
        "version": "0.9.5", "agents": agents,
        "workspaces": [["workspace_id": "w1", "label": "Example"]]
    ]]])
    return try Snapshot.decode(data)
}

@Test func acceptsEveryHerdr095AgentAndCustomReportersWithoutAWhitelist() throws {
    let kinds = herdr095Kinds + ["crush", "command-code", "prime-agent", "Acme Reviewer"]
    var agents: [[String: Any]] = kinds.enumerated().map { index, kind in
        ["pane_id": "w1:p\(index)", "workspace_id": "w1", "agent": kind,
         "agent_status": "working", "terminal_title_stripped": "Task \(index)"]
    }
    agents.append(["pane_id": "w1:shell", "workspace_id": "w1", "agent": NSNull(), "agent_status": "idle"])
    agents.append(["pane_id": "w1:empty", "workspace_id": "w1", "agent": "", "agent_status": "idle"])
    let result = try snapshot(agents)
    #expect(result.trackedAgents.count == kinds.count)
    #expect(Set(result.trackedAgents.compactMap(\.kind)) == Set(kinds))
    #expect(result.trackedAgents.allSatisfy { $0.status == .working })
    let activity = AgentActivityState(agents: result.trackedAgents, workspaces: result.workspaces)
    #expect(activity.total == kinds.count && activity.working == kinds.count)
    #expect(activity.items.count == 3)
    #expect(result.trackedAgents.first(where: { $0.kind == "Acme Reviewer" })?.kindName == "Acme Reviewer")
}

@Test func mixedAgentsKeepTypesStatesAndPaneIdentitiesInLiveActivity() throws {
    let result = try snapshot([
        ["pane_id": "w1:pi", "workspace_id": "w1", "agent": "pi", "agent_status": "idle"],
        ["pane_id": "w1:codex", "workspace_id": "w1", "agent": "codex", "agent_status": "blocked"],
        ["pane_id": "w1:claude", "workspace_id": "w1", "agent": "claude", "agent_status": "working"]
    ])
    let activity = AgentActivityState(agents: result.trackedAgents, workspaces: result.workspaces)
    #expect(activity.items.map(\.id) == ["w1:codex", "w1:claude", "w1:pi"])
    #expect(activity.items.map(\.kindName) == ["Codex", "Claude Code", "Pi"])
    #expect(activity.items.map(\.status) == [.blocked, .working, .idle])
    #expect(activity.blocked == 1 && activity.working == 1 && activity.done == 0)
}

@Test func herdrNamesAndDisplayOverridesDoNotChangeSemanticIdentity() throws {
    let result = try snapshot([
        ["pane_id": "w1:p1", "workspace_id": "w1", "agent": "claude", "agent_status": "blocked",
         "name": "Reviewer", "title": "Release review", "terminal_title_stripped": "Editor",
         "display_agent": "Code Review", "state_labels": ["blocked": "Running"]],
        ["pane_id": "w1:p2", "workspace_id": "w1", "agent": "codex", "agent_status": "working",
         "title": "Build service", "terminal_title_stripped": "Shell"]
    ])
    let reviewer = try #require(result.trackedAgents.first)
    #expect(reviewer.id == "w1:p1" && reviewer.kind == "claude")
    #expect(reviewer.title == "Reviewer" && reviewer.kindName == "Code Review")
    #expect(reviewer.status == .blocked)
    #expect(result.trackedAgents.last?.title == "Build service")
    let activity = AgentActivityState(agents: result.trackedAgents, workspaces: result.workspaces)
    #expect(activity.items.first?.kind == "claude")
    #expect(activity.items.first?.kindName == "Code Review")
}

@Test func oldActivityPayloadWithoutDisplayOverrideStillDecodes() throws {
    let data = Data("""
    {"id":"w1:p1","title":"Build","kind":"codex","status":"working","project":"Example"}
    """.utf8)
    let item = try JSONDecoder().decode(AgentActivityState.Item.self, from: data)
    #expect(item.kindName == "Codex")
}
