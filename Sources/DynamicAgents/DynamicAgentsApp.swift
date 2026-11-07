import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

@main
struct DynamicAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AgentStore.shared
    @State private var updates = UpdateController.shared
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some Scene {
        Window("Dynamic Agents", id: "dashboard") {
            DashboardView(store: store)
                .onAppear {
                    delegate.store = store
                    if !ProcessInfo.processInfo.arguments.contains("--verify-live-activity") { store.start() }
                    delegate.verifyLiveActivityIfRequested(store: store)
                }
                .task { await updates.check(manual: false) }
                .onOpenURL { url in
                    guard url.scheme == "dynamicagents", url.host == "agent",
                          let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pane" })?.value else { return }
                    Task {
                        await store.refresh()
                        if let agent = store.agents.first(where: { $0.id == id }) { await store.focus(agent) }
                    }
                }
        }
        .defaultSize(width: 820, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button(updates.menuTitle) { Task { await updates.check(manual: true) } }
                    .disabled(updates.isChecking)
            }
            CommandGroup(after: .toolbar) {
                Button(L10n.text("Refresh Status")) { Task { await store.refresh() } }.keyboardShortcut("r")
                Toggle(L10n.text("Show Menu Bar Icon"), isOn: $showMenuBarIcon)
            }
        }
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            AgentMenu(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image)
            if store.connected, store.state.blocked > 0 {
                Text("\(store.state.blocked)")
            }
        }.menuBarExtraStyle(.menu)
    }
}

struct AgentMenu: View {
    var store: AgentStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Text(store.loading ? L10n.text("Connecting…") : store.state.headline)
        Divider()
        ForEach([AgentStatus.blocked, .done, .working, .idle, .unknown], id: \.self) { status in
            let agents = store.agents.filter { $0.status == status }
            if !agents.isEmpty {
                Section(status.label) {
                    ForEach(agents) { agent in
                        Button {
                            Task { await store.focus(agent) }
                        } label: {
                            Text("\(agent.kindName) — \(agent.title)")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .disabled(!store.connected || store.focusingID != nil)
                    }
                }
            }
        }
        if let error = store.actionError { Text(error) }
        Divider()
        Button(L10n.text("Open Terminal")) { Task { await store.openTerminal() } }
            .disabled(!store.herdrConnected)
        Button(L10n.text("Open Dynamic Agents")) {
            openWindow(id: "dashboard")
            NSApp.activate(ignoringOtherApps: true)
        }
        if store.liveActivity.isEnabled {
            Button(L10n.text("Stop Live Activity")) { Task { await store.liveActivity.stop() } }
        }
        Divider()
        Button(L10n.text("Hide Menu Bar Icon")) { showMenuBarIcon = false }
        Button(L10n.text("Quit Dynamic Agents")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AgentStore?
    private var verificationStarted = false
    func verifyLiveActivityIfRequested(store: AgentStore) {
        #if NATIVE_LIVE_ACTIVITIES
        let args = ProcessInfo.processInfo.arguments
        guard NSApp.isActive, !verificationStarted, let index = args.firstIndex(of: "--verify-live-activity"), args.indices.contains(index + 1) else { return }
        verificationStarted = true
        let reportURL = URL(fileURLWithPath: args[index + 1])
        Task { await LiveActivityVerification.run(store: store, reportURL: reportURL) }
        #endif
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if let store { verifyLiveActivityIfRequested(store: store) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--verify-terminal"), args.indices.contains(index + 1) {
            let reportURL = URL(fileURLWithPath: args[index + 1])
            Task { await TerminalVerification.run(reportURL: reportURL) }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc private func sleeping() { store?.setSleeping(true) }
    @objc private func waking() { store?.setSleeping(false) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.liveActivity.isRunning else { return .terminateNow }
        Task {
            await store.liveActivity.finish()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
