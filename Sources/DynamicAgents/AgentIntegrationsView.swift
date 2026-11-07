import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

@Observable @MainActor
final class IntegrationStore {
    private(set) var integrations: [AgentIntegration] = []
    private(set) var loading = false
    private(set) var changingTarget: String?
    private(set) var error: String?
    private(set) var notice: String?
    private var client: HerdrClient?
    private var revision = 0

    func refresh(client: HerdrClient) async {
        guard changingTarget == nil else { return }
        self.client = client
        revision += 1
        let request = revision
        loading = true
        error = nil
        do {
            let integrations = try await client.integrations()
            guard request == revision else { return }
            self.integrations = integrations.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        } catch {
            guard request == revision else { return }
            self.integrations = []
            self.error = error.localizedDescription
        }
        if request == revision { loading = false }
    }

    func change(_ integration: AgentIntegration, install: Bool) async {
        guard !loading, changingTarget == nil, let client,
              integrations.contains(where: { $0.target == integration.target }) else { return }
        changingTarget = integration.target
        error = nil
        notice = nil
        do {
            try await client.changeIntegration(target: integration.target, install: install)
            notice = install ? L10n.text("Integration installed. Restart that agent to load its hooks or plugins.") : L10n.text("Integration removed. Restart that agent to unload its hooks or plugins.")
        } catch { self.error = error.localizedDescription }
        do {
            integrations = try await client.integrations().sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        } catch {
            integrations = []
            if self.error == nil { self.error = error.localizedDescription }
        }
        changingTarget = nil
    }
}

struct AgentIntegrationsView: View {
    let client: HerdrClient
    @State private var store = IntegrationStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("Agent Integrations")).font(.headline)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") {
                    Task { await store.refresh(client: client) }
                }
                .disabled(store.loading || store.changingTarget != nil)
            }.padding()
            Text(L10n.text("Run agents inside herdr to monitor them. Install hooks for session restore; supported plugins also report lifecycle state."))
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom)
            List(store.integrations) { integration in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(integration.label).font(.body.weight(.medium))
                        Text("\(integration.state.label) · \(integration.monitoringLabel)")
                            .font(.caption).foregroundStyle(.secondary)
                        if !integration.available {
                            Text(L10n.text("Agent command not found on herdr's PATH"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if store.changingTarget == integration.target { ProgressView().controlSize(.small) }
                    if integration.state == .current || integration.state == .outdated {
                        Button(L10n.text("Remove")) { Task { await store.change(integration, install: false) } }
                            .accessibilityIdentifier("integration-remove-\(integration.target)")
                    }
                    if integration.state != .current && integration.state != .unknown {
                        Button(integration.state == .outdated ? L10n.text("Update") : L10n.text("Install")) {
                            Task { await store.change(integration, install: true) }
                        }
                        .accessibilityIdentifier("integration-install-\(integration.target)")
                    }
                }
                .padding(.vertical, 4)
                .disabled(store.loading || store.changingTarget != nil)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("integration-row-\(integration.target)")
            }
            .accessibilityIdentifier("agent-integrations-list")
            if store.integrations.isEmpty, !store.loading, store.error == nil {
                Text(L10n.text("No integrations reported by herdr.")).foregroundStyle(.secondary).padding()
            }
            if let error = store.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled).padding()
            }
            if let notice = store.notice {
                Text(notice).foregroundStyle(.secondary).padding()
            }
            Text(L10n.text("Changes apply immediately to herdr's agent configuration and are separate from Save or Cancel."))
                .font(.caption).foregroundStyle(.secondary).padding()
        }
        .frame(minHeight: 300)
        .task(id: "\(client.executable)\n\(client.session)") { await store.refresh(client: client) }
    }
}
