import AppKit
import Observation
#if SWIFT_PACKAGE
import AgentCore
#endif

@Observable @MainActor
final class TerminalController {
    private(set) var detected: TerminalResolution = .unavailable
    private(set) var applications: [TerminalApplication] = []
    private(set) var isDetecting = false
    private(set) var clients: [TerminalClient] = []
    var preferredClientID: String {
        get { UserDefaults.standard.string(forKey: "terminalClientID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "terminalClientID") }
    }
    private var revision = 0
    private var discoveryError: String?
    private var chosenApplications: [String: TerminalApplication] = [:]

    func refresh(executable: String, session: String, preferredBundleID: String) async {
        revision += 1
        let request = revision
        isDetecting = true
        let processes: [ProcessRecord]
        async let endpoint = try? HerdrClient(executable: executable, session: session).socketPath()
        do {
            processes = try await Task.detached(priority: .utility) {
                try await ProcessInventory.capture(herdrExecutable: executable)
            }.value
        } catch {
            guard request == revision else { return }
            detected = .unavailable
            clients = []
            discoveryError = error.localizedDescription
            isDetecting = false
            return
        }
        let socketPath = await endpoint
        guard request == revision else { return }
        defer { isDetecting = false }
        discoveryError = nil
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> TerminalApplication? in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            return TerminalApplication(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
        }
        clients = TerminalResolver.resolveClients(processes: processes, applications: running, session: session, socketPath: socketPath)
        detected = TerminalResolver.resolve(processes: processes, applications: running, session: session, socketPath: socketPath)
        var options: [TerminalApplication] = []
        switch detected {
        case .resolved(let app): options = [app]
        case .ambiguous(let apps): options = apps
        case .unavailable: break
        }
        let identifiers = Self.knownTerminals + (preferredBundleID.isEmpty ? [] : [preferredBundleID])
        for identifier in identifiers {
            if let app = running.first(where: { $0.bundleID == identifier }) {
                options.append(app)
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier), let app = Self.application(at: url) {
                options.append(app)
            }
        }
        options.append(contentsOf: chosenApplications.values)
        applications = options.reduce(into: [String: TerminalApplication]()) { result, app in
            if result[app.bundleID] == nil { result[app.bundleID] = app }
        }.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func resolution(preferredBundleID: String) -> TerminalResolution {
        guard !preferredBundleID.isEmpty else { return detected }
        guard let app = applications.first(where: { $0.bundleID == preferredBundleID }) else { return .unavailable }
        return .resolved(app)
    }

    func status(preferredBundleID: String) -> String {
        if isDetecting { return L10n.text("Detecting terminal…") }
        if preferredBundleID.isEmpty, let discoveryError { return L10n.format("Unable to detect the terminal. %@", discoveryError) }
        switch resolution(preferredBundleID: preferredBundleID) {
        case .resolved(let app): return preferredBundleID.isEmpty ? L10n.format("Automatic · %@", app.name) : L10n.format("Selected · %@", app.name)
        case .ambiguous: return L10n.text("Multiple terminals connected; choose one in settings")
        case .unavailable: return preferredBundleID.isEmpty ? L10n.text("No connected terminal found") : L10n.text("Selected terminal app not found")
        }
    }

    typealias FocusTarget = TerminalFocusTarget

    func prepareFocus(paneID: String, preferredBundleID: String) throws -> FocusTarget {
        try selectTarget(paneID: paneID, preferredBundleID: preferredBundleID)
    }

    private func selectTarget(paneID: String?, preferredBundleID: String) throws -> FocusTarget {
        let snapshot = clients
        let preference = preferredClientID
        let anchor = try TerminalClientSelection.client(from: snapshot, paneID: paneID, preferredBundleID: preferredBundleID, preferredClientID: preference)
        let surfaces = try TerminalAutomation.surfaces(in: anchor.application)
        return try TerminalClientSelection.target(from: snapshot, surfaces: surfaces, paneID: paneID, preferredBundleID: preferredBundleID, preferredClientID: preference)
    }

    func present(_ target: FocusTarget, paneID: String) async throws {
        if let app = NSRunningApplication(processIdentifier: target.client.application.pid) {
            NSApp.yieldActivation(to: app)
            app.unhide()
        }
        try TerminalAutomation.focus(target.surface, application: target.client.application)
        if target.policy == .existingClient {
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.client.application.pid { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try await HerdrClientNavigation.open(paneID: paneID, target: target)
        }
    }

    func agentIsFocused(paneID: String, preferredBundleID: String) async throws -> Bool {
        let target = try selectTarget(paneID: paneID, preferredBundleID: preferredBundleID)
        guard try TerminalAutomation.focusedSurfaceID(in: target.client.application) == target.surface.id else { return false }
        return try await HerdrClientNavigation.currentPane(target: target) == paneID
    }

    @discardableResult
    func activate(preferredBundleID: String, paneID: String? = nil) async throws -> TerminalApplication {
        let target = try selectTarget(paneID: paneID, preferredBundleID: preferredBundleID)
        if let app = NSRunningApplication(processIdentifier: target.client.application.pid) { NSApp.yieldActivation(to: app) }
        try TerminalAutomation.focus(target.surface, application: target.client.application)
        return target.client.application
    }

    static func isTerminal(_ bundleID: String) -> Bool { knownTerminals.contains(bundleID) }

    func activateHook(_ event: DesktopHookEvent, host: NSRunningApplication) async throws {
        let records = try await ProcessInventory.capture(herdrExecutable: HerdrClient.defaultExecutable)
        let byPID = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let record = event.ancestorPIDs.compactMap { byPID[$0] }.first { candidate in
            guard candidate.tty != nil, let started = ProcessInventory.startedAt(pid: candidate.pid), started.timeIntervalSince1970 <= event.timestamp else { return false }
            var parent = candidate.parentPID
            var visited = Set<Int32>()
            while parent > 1, visited.insert(parent).inserted {
                if parent == host.processIdentifier { return true }
                guard let next = byPID[parent] else { break }
                parent = next.parentPID
            }
            return false
        }
        guard !host.isTerminated, let record, let bundle = host.bundleIdentifier, let path = host.bundleURL?.path else {
            throw HerdrError.message(L10n.text("The hook session’s terminal window is no longer available."))
        }
        let app = TerminalApplication(pid: host.processIdentifier, bundleID: bundle, name: host.localizedName ?? bundle, path: path)
        let client = TerminalClient(application: app, processID: record.pid, tty: record.tty, session: "desktop", attachedPaneID: nil)
        let surface = try TerminalSurfaceResolver.surface(for: client, surfaces: TerminalAutomation.surfaces(in: app))
        NSApp.yieldActivation(to: host)
        try TerminalAutomation.focus(surface, application: app)
    }

    func addApplication(at url: URL) -> String? {
        guard let app = Self.application(at: url) else { return nil }
        chosenApplications[app.bundleID] = app
        applications.removeAll { $0.bundleID == app.bundleID }
        applications.append(app)
        applications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return app.bundleID
    }

    private static func application(at url: URL) -> TerminalApplication? {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return TerminalApplication(pid: 0, bundleID: identifier, name: name, path: url.path)
    }

    private static let knownTerminals = [
        "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty",
        "dev.warp.Warp-Stable", "co.zeit.hyper", "com.raphaelamorim.rio", "com.tw93.kaku"
    ]
}
