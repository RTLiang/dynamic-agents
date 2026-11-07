import Foundation
import Testing
@testable import AgentCore

@Test func existingPageNavigationUsesConfiguredShortcuts() throws {
    let defaults = try HerdrNavigationKeys.parse("")
    #expect(defaults.openNavigator == [try HerdrNavigationKey("ctrl+b"), try HerdrNavigationKey("g")])
    let customized = try HerdrNavigationKeys.parse("""
    [keys]
    prefix = 'ctrl+a' # local prefix
    goto = "prefix+shift+g"
    """)
    #expect(customized.openNavigator == [try HerdrNavigationKey("ctrl+a"), try HerdrNavigationKey("shift+g")])
    let direct = try HerdrNavigationKeys.parse("keys.goto = [\"cmd+g\", \"ctrl+g\"]")
    #expect(direct.openNavigator == [try HerdrNavigationKey("command+g")])
}

@Test func unrelatedMultilineCommandsDoNotChangeNavigationBindings() throws {
    let config = #"""
    [[commands]]
    command = """
    [keys]
    prefix = "ctrl+x"
    """
    [keys]
    goto = "ctrl+g"
    """#
    #expect(try HerdrNavigationKeys.parse(config).openNavigator == [try HerdrNavigationKey("ctrl+g")])
}

@Test func ambiguousOrUnsupportedNavigationConfigurationFailsClosed() {
    for config in ["[keys]\nprefix = \"ctrl+b\"\nprefix = \"ctrl+x\"", "keys = { prefix = 'ctrl+x' }", "[keys]\ngoto = []", "[keys]\ngoto = \"unknown+g\"", "[keys]\ngoto = \"prefix+\""] {
        #expect(throws: HerdrError.self) { try HerdrNavigationKeys.parse(config) }
    }
}

private func navigatorScreen(count: Int, detail: String, searching: Bool = false) -> String {
    """
    ╭─ Go to ───────────────────────────────────────────╮
    │ / search agents and terminals       \(count) \(count == 1 ? "terminal" : "terminals") │
    │                                                   │
    │ Work                                              │
    │   Pi                                              │
    │ \(detail) │
    │ /workspace                                        │
    │ \(searching ? "search type · move ↑↓/ctrl+n/p · open enter · back esc" : "↑↓/j/k rows · ←→ workspace · / search · a/b/w/i/d filter · enter open · esc close") │
    ╰───────────────────────────────────────────────────╯
    """
}

@Test func navigatorProofReadsTheSelectedPaneAndUniqueResultCount() {
    let current = HerdrNavigatorSnapshot(screen: navigatorScreen(count: 3, detail: "Work / 1 / wB:p2"))
    #expect(current?.terminalCount == 3)
    #expect(current?.selectedPaneID == "wB:p2")
    #expect(current?.searchFocused == false)
    let filtered = HerdrNavigatorSnapshot(screen: navigatorScreen(count: 1, detail: "Work / 1 / wA:p1", searching: true))
    #expect(filtered?.terminalCount == 1)
    #expect(filtered?.selectedPaneID == "wA:p1")
    #expect(filtered?.searchFocused == true)
    #expect(HerdrNavigatorSnapshot(screen: "Go to wA:p1\n1 terminal") == nil)
}

@Test func navigatorProofNeverAcceptsATruncatedOrBackgroundPaneID() {
    let text = "Earlier output wA:p1\n" + navigatorScreen(count: 11, detail: "Work / 1 / wB:p...")
    let snapshot = HerdrNavigatorSnapshot(screen: text)
    #expect(snapshot?.terminalCount == 11)
    #expect(snapshot?.selectedPaneID == nil)
}
