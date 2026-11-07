import Foundation
import Testing
@testable import AgentCore

private func navigation(_ agents: [[String: String]]? = nil) throws -> HerdrNavigationSnapshot {
    let rows = agents ?? [
        ["pane_id": "w1:p1", "workspace_id": "w1", "tab_id": "w1:t1", "agent": "codex"],
        ["pane_id": "w1:p2", "workspace_id": "w1", "tab_id": "w1:t2", "agent": "codex"],
        ["pane_id": "w2:p1", "workspace_id": "w2", "tab_id": "w2:t1", "agent": "claude"],
    ]
    let value: [String: Any] = ["result": ["snapshot": [
        "workspaces": [["workspace_id": "w1", "label": "Example"], ["workspace_id": "w2", "label": "中文项目"]],
        "tabs": [["tab_id": "w1:t1", "workspace_id": "w1", "label": "Build"], ["tab_id": "w1:t2", "workspace_id": "w1", "label": "Review"], ["tab_id": "w2:t1", "workspace_id": "w2", "label": "Main"]],
        "agents": rows, "focused_pane_id": "w1:p1"
    ]]]
    return try HerdrNavigationSnapshot.decode(JSONSerialization.data(withJSONObject: value))
}

@Test func directNavigationFindsTheExactExistingSidebarRowWithoutOpeningAChooser() throws {
    let snapshot = try navigation()
    let screen = """
     spaces                       │ shell
     ○ Example                    │
     agents grouped               │
     ● Example · Build            │
       codex                      │
     ○ Example · Review           │
       codex                      │
     ○ 中文项目                   │
       claude                     │
    """
    #expect(snapshot.visibleAgentRow(for: "w1:p2", screen: screen) == 5)
    #expect(snapshot.visibleAgentRow(for: "w2:p1", screen: screen) == 7)
    #expect(snapshot.visibleAgentRow(for: "missing", screen: screen) == nil)
}

@Test func sidebarMatchingAllowsUnambiguousTruncationAndRejectsDuplicateLabels() throws {
    let screen = " agents grouped│\n ● Exam… · Rev…│\n   codex       │\n"
    #expect(try navigation().visibleAgentRow(for: "w1:p2", screen: screen) == 1)
    let duplicated = [
        ["pane_id": "w1:p1", "workspace_id": "w1", "tab_id": "w1:t2", "agent": "codex"],
        ["pane_id": "w1:p2", "workspace_id": "w1", "tab_id": "w1:t2", "agent": "codex"],
    ]
    #expect(try navigation(duplicated).visibleAgentRow(for: "w1:p2", screen: screen) == nil)
    #expect(try navigation().visibleAgentRow(for: "w1:p2", screen: "No sidebar") == nil)
}

@Test func directNavigationHonorsTheClientPrefixAndDoesNotRequireGoto() throws {
    let keys = try HerdrNavigationKeys.parse("[keys]\nprefix='ctrl+a'\ngoto=[]\ncycle_pane_next='prefix+shift+tab'", useNavigator: false)
    #expect(keys.openNavigator.isEmpty)
    #expect(try keys.cyclePane() == [HerdrNavigationKey("ctrl+a"), HerdrNavigationKey("shift+tab")])
    #expect(throws: (any Error).self) { try HerdrNavigationKeys.parse("[keys]\ncycle_pane_next=[]", useNavigator: false) }
}
