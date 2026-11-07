#if NATIVE_LIVE_ACTIVITIES
import OSLog

@MainActor
enum AgentFocusAction {
    static func perform(agentID: String) async throws {
        let logger = Logger(subsystem: AgentHandoff.applicationID, category: "AgentHandoff")
        logger.notice("Agent action received in main application")
        let store = AgentStore.shared
        await store.refresh()
        guard store.connected else {
            throw AgentError.message(L10n.text("Hook monitoring unavailable"))
        }
        guard store.focusingID == nil else {
            throw AgentError.message(L10n.text("Opening an app. Try again shortly."))
        }
        guard let agent = store.agents.first(where: { $0.id == agentID }) else {
            throw AgentError.message(L10n.text("This agent has ended. Refresh the Live Activity."))
        }
        await store.focus(agent, presentsError: false)
        if let error = store.actionError {
            logger.error("Agent action failed: \(error, privacy: .private)")
            throw AgentError.message(error)
        }
        logger.notice("Agent action completed")
    }
}
#endif
