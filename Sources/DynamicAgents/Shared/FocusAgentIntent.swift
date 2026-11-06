#if NATIVE_LIVE_ACTIVITIES
import AppIntents

struct FocusAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Agent in Terminal"
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .main
    static let isDiscoverable = false

    @Parameter(title: "Pane") var paneID: String

    init() { }
    init(paneID: String) { self.paneID = paneID }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = AgentStore.shared
        await store.refresh()
        guard store.connected else {
            throw HerdrError.message(store.connectionError ?? L10n.text("Unable to connect to herdr. Try again."))
        }
        guard store.focusingID == nil else {
            throw HerdrError.message(L10n.text("Switching terminals. Try again shortly."))
        }
        guard let agent = store.agents.first(where: { $0.id == paneID }) else {
            throw HerdrError.message(L10n.text("This agent has ended. Refresh the Live Activity."))
        }
        await store.focus(agent)
        if let error = store.actionError { throw HerdrError.message(error) }
        #endif
        return .result()
    }
}
#endif
