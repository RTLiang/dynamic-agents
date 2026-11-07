import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

struct IntegrationManagementView: View {
    let client: HerdrClient
    var body: some View {
        TabView {
            AgentIntegrationsView(client: client).tabItem { Text("herdr") }
            DesktopHooksView().tabItem { Text(L10n.text("Desktop Clients")) }
        }
    }
}

struct DesktopHooksView: View {
    @State private var installed: [DesktopHookSource: Bool] = [:]
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
                        Text(installed[source].map { $0 ? L10n.text("Hook Installed") : L10n.text("Not Installed") } ?? L10n.text("Unknown"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if changing == source { ProgressView().controlSize(.small) }
                    Button(installed[source] == true ? L10n.text("Remove") : L10n.text("Install")) {
                        Task { await change(source) }
                    }
                    .disabled(loading || changing != nil || installed[source] == nil)
                    .accessibilityIdentifier("desktop-hook-\(source.rawValue)")
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("desktop-hooks-list")
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let notice { Text(notice).foregroundStyle(.secondary) }
            Text(L10n.text("Restart the client after installation. Codex requires reviewing and trusting the hooks in Settings > Hooks. Managed policies and remote runtimes may prevent local reporting."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Desktop actions open the host app; selecting an exact conversation is not supported."))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("Refresh")) { Task { await refresh() } }.disabled(loading || changing != nil)
        }
        .padding()
        .task { await refresh() }
    }

    private func refresh() async {
        loading = true
        error = nil
        for source in DesktopHookSource.allCases {
            do { installed[source] = try await DesktopHooks.configure(source, action: "status") }
            catch { installed[source] = nil; self.error = error.localizedDescription }
        }
        loading = false
    }

    private func change(_ source: DesktopHookSource) async {
        guard changing == nil else { return }
        changing = source
        error = nil
        do {
            installed[source] = try await DesktopHooks.configure(source, action: installed[source] == true ? "remove" : "install")
            notice = L10n.text("Restart the client and review its hook permissions. New task events will appear automatically.")
        } catch { self.error = error.localizedDescription }
        changing = nil
    }
}
