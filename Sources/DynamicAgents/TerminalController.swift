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
    private var revision = 0
    private var discoveryError: String?
    private var chosenApplications: [String: TerminalApplication] = [:]

    func refresh(executable: String, session: String, preferredBundleID: String) async {
        revision += 1
        let request = revision
        isDetecting = true
        let processes: [ProcessRecord]
        do {
            processes = try await Task.detached(priority: .utility) {
                try await ProcessInventory.capture(herdrExecutable: executable)
            }.value
        } catch {
            guard request == revision else { return }
            detected = .unavailable
            discoveryError = error.localizedDescription
            isDetecting = false
            return
        }
        guard request == revision else { return }
        defer { isDetecting = false }
        discoveryError = nil
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> TerminalApplication? in
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            return TerminalApplication(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
        }
        detected = TerminalResolver.resolve(processes: processes, applications: running, session: session)
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

    @discardableResult
    func activate(preferredBundleID: String) async throws -> TerminalApplication {
        let app: TerminalApplication
        switch resolution(preferredBundleID: preferredBundleID) {
        case .resolved(let resolved): app = resolved
        case .ambiguous: throw HerdrError.message(L10n.text("Multiple terminals are connected to this session. Choose one in settings."))
        case .unavailable:
            throw HerdrError.message(preferredBundleID.isEmpty ? L10n.text("No terminal found for this session. Open herdr in a terminal and try again.") : L10n.text("The selected terminal app was not found. Choose it again in settings."))
        }
        if app.pid > 0, let running = NSRunningApplication(processIdentifier: app.pid), !running.isTerminated, running.bundleIdentifier == app.bundleID {
            running.unhide()
            NSApp.yieldActivation(to: running)
            guard running.activate(options: [.activateAllWindows]) else {
                throw HerdrError.message(L10n.format("macOS could not activate %@. Try again.", app.name))
            }
            return app
        }
        guard !preferredBundleID.isEmpty else {
            throw HerdrError.message(L10n.text("The detected terminal has quit. Open herdr again and retry."))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration)
        return app
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
