import AppKit
import Observation
#if SWIFT_PACKAGE
import AgentCore
#endif

@Observable @MainActor
final class UpdateController {
    static let shared = UpdateController()
    private(set) var isChecking = false
    private(set) var availableRelease: AppRelease?
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var menuTitle: String { availableRelease.map { L10n.format("Update to %@…", $0.version.description) } ?? L10n.text("Check for Updates…") }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        let defaults = UserDefaults.standard
        if !manual {
            guard defaults.object(forKey: "automaticallyCheckForUpdates") as? Bool ?? true else { return }
            guard Date.now.timeIntervalSince1970 - defaults.double(forKey: "lastUpdateAttempt") > 86_400 else { return }
        }
        isChecking = true
        defaults.set(Date.now.timeIntervalSince1970, forKey: "lastUpdateAttempt")
        defer { isChecking = false }
        do {
            let release = try await AppRelease.latest()
            guard let current = ReleaseVersion(Self.currentVersion) else { throw HerdrError.message(L10n.text("The installed app has an invalid version.")) }
            availableRelease = release.flatMap { $0.version > current ? $0 : nil }
            if manual {
                if let availableRelease {
                    let alert = NSAlert()
                    alert.messageText = L10n.format("Dynamic Agents %@ is available", availableRelease.version.description)
                    alert.informativeText = L10n.format("Installed version: %@. The release page includes the download and SHA-256 checksum. Requires macOS 27.3 or later.", Self.currentVersion)
                    alert.addButton(withTitle: L10n.text("View Release"))
                    alert.addButton(withTitle: L10n.text("Cancel"))
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(availableRelease.pageURL) }
                } else {
                    show(L10n.text("No Updates Available"), detail: release == nil ? L10n.text("No compatible stable release has been published yet.") : L10n.format("Dynamic Agents %@ is up to date.", Self.currentVersion))
                }
            }
        } catch {
            if manual { show(L10n.text("Unable to Check for Updates"), detail: error.localizedDescription) }
        }
    }

    private func show(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.text("OK"))
        alert.runModal()
    }
}
