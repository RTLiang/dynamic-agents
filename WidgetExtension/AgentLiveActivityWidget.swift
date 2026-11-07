import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DynamicAgentsWidgets: WidgetBundle {
    var body: some Widget { AgentLiveActivityWidget() }
}

struct AgentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            ActivityPanel(state: context.state, stale: context.isStale)
                .widgetURL(AgentHandoff.dashboardURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    AgentActivityContentView(state: context.state, stale: context.isStale)
                        .padding(.vertical, 4)
                }
            } compactLeading: {
                Text(context.isStale ? L10n.text("Stale") : context.state.compactLabels().first ?? "—")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.leading, 5)
                    .padding(.trailing, context.isStale || context.state.compactLabels().count < 2 ? 7 : 0)
                    .accessibilityLabel(context.isStale ? L10n.text("Status out of date") : context.state.compactLabels(accessibility: true).joined(separator: ", "))
            } compactTrailing: {
                if !context.isStale, context.state.connected, context.state.compactLabels().count > 1 {
                    Text(context.state.compactLabels()[1])
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.trailing, 7)
                        .accessibilityHidden(true)
                }
            } minimal: {
                HStack(spacing: 3) {
                    if !context.isStale, context.state.connected {
                        Image(systemName: context.state.working > 0 ? "play.fill" : "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(count(context)).font(.system(size: 15, weight: .medium).monospacedDigit())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(context.isStale ? L10n.text("Status out of date") : context.state.compactLabels(accessibility: true).joined(separator: ", "))
            }
            .widgetURL(AgentHandoff.dashboardURL)
        }
    }

    private func count(_ context: ActivityViewContext<AgentActivityAttributes>) -> String {
        guard !context.isStale, context.state.connected else { return "—" }
        let count = context.state.total
        return count > 99 ? "99+" : "\(count)"
    }
}
