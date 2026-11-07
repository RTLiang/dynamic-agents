import Foundation
import Testing
@testable import AgentCore

private let english = Locale(identifier: "en")
private let chinese = Locale(identifier: "zh-Hans")

@Test func localizesStatusesAndActionsInBothLanguages() {
    #expect(L10n.text("Running", locale: english) == "Running")
    #expect(L10n.text("Running", locale: chinese) == "运行中")
    #expect(AgentStatus.working.label(locale: english) == "Running")
    #expect(AgentStatus.done.label(locale: chinese) == "已完成")
    #expect(L10n.format("%@, %@, %@", "Codex", "Example", "已完成", locale: chinese) == "Codex，Example，已完成")
    #expect(L10n.text("Open in Terminal", locale: english) == "Open in Terminal")
    #expect(L10n.text("Open in Terminal", locale: chinese) == "在终端中打开")
    #expect(L10n.text("Connection Settings", locale: chinese) == "连接设置")
}

@Test func englishCountsUseSingularAndPluralAndChineseUsesItsOwnOrder() {
    #expect(L10n.format("agent.count", Int64(0), locale: english) == "0 agents")
    #expect(L10n.format("agent.count", Int64(1), locale: english) == "1 agent")
    #expect(L10n.format("agent.count", Int64(2), locale: english) == "2 agents")
    #expect(L10n.format("agent.running", Int64(1), locale: english) == "1 agent is running")
    #expect(L10n.format("agent.running", Int64(2), locale: english) == "2 agents are running")
    #expect(L10n.format("session.more", Int64(1), locale: english) == "1 more session")
    #expect(L10n.format("session.more", Int64(3), locale: english) == "3 more sessions")
    #expect(L10n.format("session.more", Int64(3), locale: chinese) == "还有 3 个会话")
    #expect(L10n.format("agent.count", Int64(2), locale: chinese) == "2 个 Agent")
    #expect(L10n.format("session.noun", Int64(1), locale: english) == "Session")
    #expect(L10n.format("session.noun", Int64(2), locale: english) == "Sessions")
    #expect(L10n.format("session.noun", Int64(2), locale: chinese) == "会话")
}

@Test func regionalAndUnsupportedLocalesChooseSupportedResources() {
    #expect(L10n.text("Completed", locale: Locale(identifier: "en-GB")) == "Completed")
    #expect(L10n.text("Completed", locale: Locale(identifier: "zh-CN")) == "已完成")
    #expect(L10n.text("Completed", locale: Locale(identifier: "fr-FR")) == "Completed")
    #expect(L10n.text("Future localization key", locale: chinese) == "Future localization key")
}

@Test func translatedMessagesPreserveRuntimeNamesAndLiteralPercentSigns() {
    let name = "Terminal 100% %@ 中文"
    #expect(L10n.format("Automatic · %@", name, locale: english) == "Automatic · \(name)")
    #expect(L10n.format("Automatic · %@", name, locale: chinese) == "自动识别 · \(name)")
    #expect(L10n.format("macOS could not activate %@. Try again.", "Ghostty", locale: english) == "macOS could not activate Ghostty. Try again.")
}

@Test func liveActivityCarriesItsAppLanguageAcrossTheWidgetBoundary() throws {
    var state = AgentActivityState(agents: [], workspaces: [], languageIdentifier: "zh-Hans")
    state.working = 2
    state.done = 1
    state.total = 3
    let restored = try JSONDecoder().decode(AgentActivityState.self, from: JSONEncoder().encode(state))
    #expect(restored.compactLabels() == ["2 运行", "1 完成"])
    #expect(restored.compactLabels(accessibility: true) == ["2 运行中", "1 已完成"])
    #expect(AgentStatus.done.label(locale: restored.locale) == "已完成")
    state.languageIdentifier = "en"
    #expect(state.compactLabels() == ["2 Run", "1 Done"])
    #expect(L10n.text("Open Agent", locale: state.locale) == "Open Agent")
}

@Test func olderActivityPayloadsWithoutLanguageStillDecode() throws {
    let state = AgentActivityState(agents: [], workspaces: [])
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    object.removeValue(forKey: "languageIdentifier")
    let decoded = try JSONDecoder().decode(AgentActivityState.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.languageIdentifier == nil)
    #expect(decoded.locale.identifier == L10n.preferredLanguage)
}

@Test func compactIslandShowsCountsAndStatusesForBothActiveAndCompletedAgents() {
    var state = AgentActivityState(agents: [], workspaces: [])
    state.working = 2
    state.done = 1
    state.total = 3
    #expect(state.compactLabels(locale: english) == ["2 Run", "1 Done"])
    #expect(state.compactLabels(locale: chinese) == ["2 运行", "1 完成"])
    #expect(state.compactLabels(locale: english, accessibility: true) == ["2 running", "1 completed"])
    state.working = 0
    #expect(state.compactLabels(locale: english) == ["1 Done"])
    state.done = 100
    #expect(state.compactLabels(locale: english) == ["99+ Done"])
    state.connected = false
    #expect(state.compactLabels(locale: english) == ["Offline"])
}
