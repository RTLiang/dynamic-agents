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

    struct FocusTarget {
        let client: TerminalClient
        let surface: TerminalSurface
        let policy: TerminalFocusPolicy
    }

    func prepareFocus(paneID: String, preferredBundleID: String) throws -> FocusTarget {
        let client = try selectClient(paneID: paneID, preferredBundleID: preferredBundleID)
        let surfaces = try TerminalAutomation.surfaces(in: client.application)
        let surface = try TerminalSurfaceResolver.surface(for: client, surfaces: surfaces)
        return FocusTarget(client: client, surface: surface, policy: TerminalFocusPolicy.resolve(client: client, paneID: paneID))
    }

    func present(_ target: FocusTarget, paneID: String, executable: String, session: String) throws {
        if let app = NSRunningApplication(processIdentifier: target.client.application.pid) { NSApp.yieldActivation(to: app) }
        if target.policy == .dedicatedAttachment {
            try TerminalAutomation.attach(paneID: paneID, executable: executable, session: session, in: target.surface, application: target.client.application)
        } else {
            try TerminalAutomation.focus(target.surface, application: target.client.application)
        }
    }

    func attachmentIsFocused(paneID: String, preferredBundleID: String) throws -> Bool {
        let client = try selectClient(paneID: paneID, preferredBundleID: preferredBundleID)
        guard client.attachedPaneID == paneID else { return false }
        let surface = try TerminalSurfaceResolver.surface(for: client, surfaces: TerminalAutomation.surfaces(in: client.application))
        return try TerminalAutomation.focusedSurfaceID(in: client.application) == surface.id
    }

    private func selectClient(paneID: String?, preferredBundleID: String) throws -> TerminalClient {
        let candidates = clients.filter { preferredBundleID.isEmpty || $0.application.bundleID == preferredBundleID }
        if let paneID {
            let attached = candidates.filter { $0.attachedPaneID == paneID }
            if attached.count == 1 { return attached[0] }
            if let selected = attached.first(where: { $0.id == preferredClientID }) { return selected }
            if attached.count > 1 { throw HerdrError.message(L10n.text("Select the exact herdr window in settings; no other window will be changed.")) }
        }
        if !preferredClientID.isEmpty {
            guard let selected = candidates.first(where: { $0.id == preferredClientID }) else {
                throw HerdrError.message(L10n.text("The selected herdr window has closed. Select its replacement in settings."))
            }
            return selected
        }
        let normal = candidates.filter { $0.attachedPaneID == nil }
        if normal.count == 1 { return normal[0] }
        if candidates.count == 1 { return candidates[0] }
        throw HerdrError.message(L10n.text("Select the exact herdr window in settings; no other window will be changed."))
    }

    @discardableResult
    func activate(preferredBundleID: String, paneID: String? = nil) async throws -> TerminalApplication {
        let client = try selectClient(paneID: paneID, preferredBundleID: preferredBundleID)
        let surface = try TerminalSurfaceResolver.surface(for: client, surfaces: TerminalAutomation.surfaces(in: client.application))
        if let app = NSRunningApplication(processIdentifier: client.application.pid) { NSApp.yieldActivation(to: app) }
        try TerminalAutomation.focus(surface, application: client.application)
        return client.application
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
