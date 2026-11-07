#if NATIVE_LIVE_ACTIVITIES
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
                Text(state.connected ? L10n.text("Status out of date") : L10n.text("Connection lost"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            ForEach(state.items) { agent in
                Link(destination: AgentHandoff.url(for: agent.id)) {
                    HStack(spacing: 12) {
                        Text(agent.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(agent.status.label)
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
                .accessibilityLabel("\(agent.kindName)，\(agent.title)，\(agent.status.label)")
                .accessibilityHint(L10n.text("Open Agent"))
            }
            if state.total > state.items.count {
                Link(L10n.format("session.more", Int64(state.total - state.items.count)), destination: AgentHandoff.dashboardURL)
                    .buttonStyle(.plain)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}
#endif
