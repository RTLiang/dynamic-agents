import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

struct SettingsView: View {
    @Bindable var store: AgentStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showMenuBarIcon") private var savedMenuBarIcon = true
    @State private var showMenuBarIcon = true
    @AppStorage("completionWindowMinutes") private var savedCompletionMinutes = 10
    @State private var completionMinutes = 10
    @AppStorage("automaticallyCheckForUpdates") private var savedAutomaticUpdates = true
    @State private var automaticUpdates = true
    @State private var showingHooks = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.text("Appearance")) {
                    Toggle(L10n.text("Show Menu Bar Icon"), isOn: $showMenuBarIcon)
                }
                Section(L10n.text("Live Activity")) {
                    LabeledContent(L10n.text("Show Completed For")) {
                        HStack {
                            TextField(L10n.text("Minutes"), value: $completionMinutes, format: .number)
                                .labelsHidden().textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing).frame(width: 64)
                                .accessibilityLabel(L10n.text("Minutes"))
                                .accessibilityIdentifier("completion-window-minutes")
                            Text(L10n.text("Minutes")).foregroundStyle(.secondary)
                            Stepper(L10n.text("Show Completed For"), value: $completionMinutes, in: 1...1440).labelsHidden()
                        }.fixedSize(horizontal: true, vertical: false)
                    }
                    Button(L10n.text("Restart Live Activity")) {
                        Task { await store.liveActivity.restart(state: store.activityState) }
                    }
                    .accessibilityIdentifier("restart-live-activity")
                    .disabled(!store.liveActivity.isSupported || !store.liveActivity.isEnabled || store.liveActivity.isStarting || store.activityState.total == 0)
                }
                Section(L10n.text("Agent Hooks")) {
                    Button(L10n.text("Manage Agent Hooks…")) { showingHooks = true }
                        .accessibilityIdentifier("manage-agent-hooks")
                    Text(L10n.text("Sessions come from agent lifecycle hooks. Opening a session activates its host app."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Updates")) {
                    Toggle(L10n.text("Automatically Check for Updates"), isOn: $automaticUpdates)
                    Button(L10n.text("Check for Updates…")) { Task { await UpdateController.shared.check(manual: true) } }
                        .disabled(UpdateController.shared.isChecking)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Save")) {
                    savedAutomaticUpdates = automaticUpdates
                    savedMenuBarIcon = showMenuBarIcon
                    savedCompletionMinutes = min(max(completionMinutes, 1), 1440)
                    Task { await store.refresh() }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }.padding()
        }
        .frame(width: 520)
        .onAppear {
            automaticUpdates = savedAutomaticUpdates
            showMenuBarIcon = savedMenuBarIcon
            completionMinutes = min(max(savedCompletionMinutes, 1), 1440)
        }
        .sheet(isPresented: $showingHooks) {
            VStack(spacing: 0) {
                DesktopHooksView()
                Divider()
                HStack {
                    Spacer()
                    Button(L10n.text("Done")) { showingHooks = false }.keyboardShortcut(.defaultAction)
                }.padding()
            }.frame(width: 620, height: 560)
        }
    }
}
