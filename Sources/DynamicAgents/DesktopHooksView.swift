import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

struct IntegrationManagementView: View {
    let client: HerdrClient
    @State private var desktopSelected = false

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("Agent Integrations"), selection: $desktopSelected) {
                Text("herdr").tag(false)
                Text(L10n.text("Desktop Clients")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            .padding(.vertical, 12)
            .accessibilityIdentifier("integration-source-picker")
            Divider()
            ZStack {
                AgentIntegrationsView(client: client)
                    .opacity(desktopSelected ? 0 : 1)
                    .allowsHitTesting(!desktopSelected)
                    .disabled(desktopSelected)
                    .accessibilityHidden(desktopSelected)
                DesktopHooksView()
                    .opacity(desktopSelected ? 1 : 0)
                    .allowsHitTesting(desktopSelected)
                    .disabled(!desktopSelected)
                    .accessibilityHidden(!desktopSelected)
            }
        }
    }
}

struct DesktopHooksView: View {
    @State private var installations: [DesktopHookSource: DesktopHookInstallation] = [:]
    @State private var changing: DesktopHookSource?
    @State private var loading = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Desktop Clients")).font(.headline)
            Text(L10n.text("Receive local lifecycle hooks from desktop coding agents and IDEs, including sessions outside herdr. Normal chat windows are not tracked."))
                .foregroundStyle(.secondary)
            List(DesktopHookSource.allCases) { source in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.label).font(.body.weight(.medium))
                        Text(installations[source].map { state in
                            state.installed ? (state.current ? L10n.text("Hook Installed") : L10n.text("Update Available")) : L10n.text("Not Installed")
                        } ?? L10n.text("Unknown"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if changing == source { ProgressView().controlSize(.small) }
                    if let state = installations[source], state.installed && !state.current {
                        Button(L10n.text("Update")) { Task { await change(source, action: "install") } }
                            .disabled(loading || changing != nil)
                            .accessibilityIdentifier("desktop-hook-update-\(source.rawValue)")
                    }
                    Button(installations[source]?.installed == true ? L10n.text("Remove") : L10n.text("Install")) {
                        let action = installations[source]?.installed == true ? "remove" : "install"
                        Task { await change(source, action: action) }
                    }
                    .disabled(loading || changing != nil || installations[source] == nil)
                    .accessibilityIdentifier("desktop-hook-\(source.rawValue)")
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("desktop-hooks-list")
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let notice { Text(notice).foregroundStyle(.secondary) }
            Text(L10n.text("Restart the client after installation. Codex requires reviewing and trusting the hooks in Settings > Hooks. Managed policies and remote runtimes may prevent local reporting."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Desktop actions open the host app; selecting an exact conversation is not supported."))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("Refresh")) { Task { await refresh() } }
                .disabled(loading || changing != nil)
                .accessibilityIdentifier("desktop-hooks-refresh")
        }
        .padding()
        .task { await refresh() }
    }

    private func refresh() async {
        loading = true
        error = nil
        for source in DesktopHookSource.allCases {
            do { installations[source] = try await DesktopHooks.installation(source) }
            catch { installations[source] = nil; self.error = error.localizedDescription }
        }
        loading = false
    }

    private func change(_ source: DesktopHookSource, action: String) async {
        guard changing == nil else { return }
        changing = source
        error = nil
        do {
            _ = try await DesktopHooks.configure(source, action: action)
            await refresh()
            notice = L10n.text("Restart the client and review its hook permissions. New task events will appear automatically.")
        } catch { self.error = error.localizedDescription }
        changing = nil
    }
}
