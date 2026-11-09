import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

struct DashboardView: View {
    @Bindable var store: AgentStore
    @State private var filter: AgentStatus?
    @State private var search = ""
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\AgentTableItem.statusOrder), KeyPathComparator(\AgentTableItem.title)]
    @State private var showingSettings = false

    private var visibleAgents: [AgentTableItem] {
        store.agents.map { AgentTableItem(agent: $0, project: $0.projectName) }
            .filter {
                (filter == nil || $0.agent.status == filter) &&
                (search.isEmpty || "\($0.title) \($0.project) \($0.kind)".localizedCaseInsensitiveContains(search))
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(visibleAgents, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(L10n.text("Agent"), value: \.title) { item in
                    Text(item.title).lineLimit(1).truncationMode(.middle).help(item.title)
                }.width(min: 180, ideal: 340)
                TableColumn(L10n.text("Project"), value: \.project) { item in
                    Text(item.project).lineLimit(1).truncationMode(.middle)
                }.width(min: 100, ideal: 160)
                TableColumn(L10n.text("Type"), value: \.kind) { item in
                    Text(item.kind).lineLimit(1).help(item.kind)
                }.width(min: 90, ideal: 120)
                TableColumn(L10n.text("Status"), value: \.statusOrder) { item in
                    Text(store.focusingID == item.id ? L10n.text("Opening…") : item.agent.status.label)
                }.width(min: 90, ideal: 110)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .accessibilityIdentifier("agents-table")
            .contextMenu(forSelectionType: String.self) { ids in
                Button(L10n.text("Open App")) { openAgent(ids.first) }
                    .disabled(ids.isEmpty || !store.connected || store.focusingID != nil)
            } primaryAction: { ids in
                openAgent(ids.first)
            }
            .onKeyPress(.return) {
                guard selection != nil else { return .ignored }
                openAgent(selection)
                return .handled
            }
            .overlay {
                if visibleAgents.isEmpty {
                    ContentUnavailableView(
                        store.loading ? L10n.text("Connecting…") : search.isEmpty && filter == nil ? L10n.text("No Agents") : L10n.text("No Matching Agents"),
                        systemImage: "list.bullet",
                        description: Text(store.loading ? "" : L10n.text("Install an agent hook in Settings, then start a coding turn."))
                    )
                }
            }
            if let error = store.liveActivity.message {
                Divider()
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button(L10n.text("Settings…")) { showingSettings = true }
                }.padding(10)
            }
            Divider()
            HStack {
                Text(L10n.format("agent.count", Int64(visibleAgents.count)))
                if !store.connected { Text(L10n.text("· Status may be out of date")) }
                Spacer()
                Text(store.connected ? L10n.text("Monitoring hooks") : L10n.text("Monitoring paused"))
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(minWidth: 640, minHeight: 360)
        .searchable(text: $search, placement: .toolbar, prompt: L10n.text("Search agents or projects"))
        .toolbar {
            ToolbarItem {
                Picker(L10n.text("Status"), selection: $filter) {
                    Text(L10n.text("All Statuses")).tag(nil as AgentStatus?)
                    ForEach(AgentStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(Optional(status))
                    }
                }.pickerStyle(.menu)
                .accessibilityIdentifier("agent-status-filter")
            }
            ToolbarItem {
                Button(L10n.text("Open App"), systemImage: "arrow.up.forward.app") {
                    openAgent(selection)
                }
                .disabled(store.focusingID != nil || selection == nil || !store.connected)
                .help(L10n.text("Activate the selected session's host app"))
                .keyboardShortcut(.return, modifiers: .command)
            }
            ToolbarItem {
                Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                    .help(L10n.text("Refresh Status"))
            }
            ToolbarItem {
                Toggle(L10n.text("Live Activity"), isOn: Binding(
                    get: { store.liveActivity.isEnabled },
                    set: { enabled in
                        Task {
                            if enabled { await store.liveActivity.start(state: store.activityState) }
                            else { await store.liveActivity.stop() }
                        }
                    }
                ))
                .toggleStyle(.button)
                .disabled(!store.liveActivity.isSupported || store.liveActivity.isStarting)
                .help(store.liveActivity.isEnabled ? L10n.text("Turn off Live Activity") : L10n.text("Show working or recently completed sessions"))
            }
            ToolbarItem {
                Button(L10n.text("Settings"), systemImage: "gearshape") { showingSettings = true }
                    .help(L10n.text("Settings"))
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .onChange(of: visibleAgents.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(store: store) }
        .alert(L10n.text("Action Failed"), isPresented: Binding(get: { store.presentsActionError && store.actionError != nil }, set: { if !$0 { store.actionError = nil } })) {
            Button(L10n.text("OK")) { store.actionError = nil }
        } message: { Text(store.actionError ?? "") }
    }

    private func openAgent(_ id: String?) {
        guard let id, let agent = store.agents.first(where: { $0.id == id }), store.connected, store.focusingID == nil else { return }
        Task { await store.focus(agent) }
    }
}

private struct AgentTableItem: Identifiable {
    let agent: Agent
    let project: String
    var id: String { agent.id }
    var title: String { agent.title }
    var kind: String { agent.kindName }
    var statusOrder: Int { agent.status.priority }
}
