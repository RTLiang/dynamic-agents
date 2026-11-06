import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import AgentCore
#endif

struct ConnectionSettings: View {
    @Bindable var store: AgentStore
    @Environment(\.dismiss) private var dismiss
    @State private var executable = ""
    @State private var session = ""
    @State private var terminal = ""
    @State private var selectionError: String?
    @AppStorage("showMenuBarIcon") private var savedMenuBarIcon = true
    @State private var showMenuBarIcon = true
    @AppStorage("completionWindowMinutes") private var savedCompletionMinutes = 10
    @State private var completionMinutes = 10

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.text("Appearance")) {
                    Toggle(L10n.text("Show Menu Bar Icon"), isOn: $showMenuBarIcon)
                        .accessibilityLabel(L10n.text("Show Menu Bar Icon"))
                }
                Section(L10n.text("Live Activity")) {
                    LabeledContent(L10n.text("Show Completed For")) {
                        HStack {
                            TextField(L10n.text("Minutes"), value: $completionMinutes, format: .number)
                                .frame(width: 64)
                                .accessibilityLabel(L10n.text("Minutes"))
                                .accessibilityIdentifier("completion-window-minutes")
                            Text(L10n.text("Minutes")).foregroundStyle(.secondary)
                            Stepper(L10n.text("Show Completed For"), value: $completionMinutes, in: 1...1440)
                                .labelsHidden()
                        }
                    }
                }
                Section(L10n.text("Connection")) {
                    LabeledContent(L10n.text("herdr Path")) {
                        HStack {
                            TextField("herdr", text: $executable)
                            Button(L10n.text("Choose…")) {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url { executable = url.path }
                            }
                        }
                    }
                    TextField(L10n.text("Session Name"), text: $session, prompt: Text(L10n.text("Default Session")))
                }
                Section(L10n.text("Terminal")) {
                    Picker(L10n.text("Open With"), selection: $terminal) {
                        Text(L10n.text("Automatic")).tag("")
                        Divider()
                        ForEach(store.terminal.applications, id: \.bundleID) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                        if !terminal.isEmpty, !store.terminal.applications.contains(where: { $0.bundleID == terminal }) {
                            Text(L10n.text("Selected app unavailable")).tag(terminal)
                        }
                    }
                    Text(store.terminal.status(preferredBundleID: terminal)).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("Detect Again")) { Task { await store.refreshTerminals() } }
                            .disabled(store.terminal.isDetecting)
                        Button(L10n.text("Choose Another App…")) { chooseApplication() }
                    }
                    if let selectionError { Text(selectionError).foregroundStyle(.red) }
                }
                if executable != store.executable || session != store.session {
                    Text(L10n.text("Changing the path or session ends the current Live Activity."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Save")) {
                    let path = executable.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = session.trimmingCharacters(in: .whitespacesAndNewlines)
                    savedMenuBarIcon = showMenuBarIcon
                    savedCompletionMinutes = min(max(completionMinutes, 1), 1440)
                    Task { await store.applySettings(executable: path, session: name, terminalBundleID: terminal) }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
                    .disabled(executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding()
        }
        .frame(width: 520)
        .onAppear {
            executable = store.executable; session = store.session; terminal = store.terminalBundleID
            showMenuBarIcon = savedMenuBarIcon
            completionMinutes = min(max(savedCompletionMinutes, 1), 1440)
        }
        .task { await store.refreshTerminals() }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let identifier = store.terminal.addApplication(at: url) {
            terminal = identifier
            selectionError = nil
        } else {
            selectionError = L10n.text("Choose a valid macOS application.")
        }
    }
}
