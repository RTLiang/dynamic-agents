#if NATIVE_LIVE_ACTIVITIES
import AppIntents
import SwiftUI

struct ActivityPanel: View {
    let state: AgentActivityState
    let stale: Bool

    var body: some View {
        AgentActivityContentView(state: state, stale: stale)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

struct AgentActivityContentView: View {
    let state: AgentActivityState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if stale || !state.connected {
                Text(state.connected ? L10n.text("Status out of date", locale: state.locale) : L10n.text("Connection lost", locale: state.locale))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            ForEach(state.items) { agent in
                Button(intent: FocusAgentIntent(agentID: agent.id, languageIdentifier: state.languageIdentifier)) {
                    HStack(spacing: 12) {
                        Text(agent.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(agent.status.label(locale: state.locale))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(stale || !state.connected)
                .accessibilityIdentifier("focus-agent-\(agent.id)")
                .accessibilityLabel(L10n.format("%@, %@, %@", agent.kindName, agent.title, agent.status.label(locale: state.locale), locale: state.locale))
                .accessibilityHint(L10n.text("Open App", locale: state.locale))
            }
            if state.total > state.items.count {
                Link(L10n.format("session.more", Int64(state.total - state.items.count), locale: state.locale), destination: AgentHandoff.dashboardURL)
                    .buttonStyle(.plain)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
#endif
