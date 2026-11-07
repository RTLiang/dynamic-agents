import Foundation

public struct TerminalFocusTarget: Sendable {
    public let client: TerminalClient
    public let surface: TerminalSurface
    public let policy: TerminalFocusPolicy
}

public enum TerminalClientSelection {
    public static func target(from clients: [TerminalClient], surfaces: [TerminalSurface], paneID: String?, preferredBundleID: String, preferredClientID: String) throws -> TerminalFocusTarget {
        let anchor = try client(from: clients, paneID: paneID, preferredBundleID: preferredBundleID, preferredClientID: preferredClientID)
        let surface = try TerminalSurfaceResolver.surface(for: anchor, surfaces: surfaces)
        if let paneID, let attached = anchor.attachedPaneID, attached != paneID {
            throw HerdrError.message(L10n.text("This view is attached to another agent. Select a herdr window in settings."))
        }
        let policy = paneID.map { TerminalFocusPolicy.resolve(client: anchor, paneID: $0) } ?? .existingClient
        return TerminalFocusTarget(client: anchor, surface: surface, policy: policy)
    }

    public static func client(from clients: [TerminalClient], paneID: String?, preferredBundleID: String, preferredClientID: String) throws -> TerminalClient {
        let candidates = clients.filter { preferredBundleID.isEmpty || $0.application.bundleID == preferredBundleID }
        if !preferredClientID.isEmpty {
            guard let selected = candidates.first(where: { $0.id == preferredClientID }) else {
                throw HerdrError.message(L10n.text("The selected herdr window has closed. Select its replacement in settings."))
            }
            return selected
        }
        let normal = candidates.filter { $0.attachedPaneID == nil }
        if normal.count == 1 { return normal[0] }
        if normal.isEmpty, let paneID {
            let attached = candidates.filter { $0.attachedPaneID == paneID }
            if attached.count == 1 { return attached[0] }
        }
        if candidates.count == 1 { return candidates[0] }
        throw HerdrError.message(L10n.text("Select the exact herdr window in settings; no other window will be changed."))
    }
}
