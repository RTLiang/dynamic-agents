import Foundation

public struct TerminalFocusTarget: Sendable {
    public let client: TerminalClient
    public let surface: TerminalSurface
    public let policy: TerminalFocusPolicy
}

public enum TerminalClientSelection {
    public static func target(from clients: [TerminalClient], surfaces: [TerminalSurface], paneID: String?, preferredBundleID: String, preferredClientID: String) throws -> TerminalFocusTarget {
        let anchor = try client(from: clients, paneID: paneID, preferredBundleID: preferredBundleID, preferredClientID: preferredClientID)
        let anchorSurface = try TerminalSurfaceResolver.surface(for: anchor, surfaces: surfaces)
        var selected = anchor
        var selectedSurface = anchorSurface
        if let paneID, !preferredClientID.isEmpty, anchor.attachedPaneID != paneID {
            let matches = clients.compactMap { candidate -> (TerminalClient, TerminalSurface)? in
                guard candidate.application == anchor.application, candidate.session == anchor.session, candidate.attachedPaneID == paneID,
                      let surface = try? TerminalSurfaceResolver.surface(for: candidate, surfaces: surfaces),
                      surface.windowID == anchorSurface.windowID else { return nil }
                return (candidate, surface)
            }
            guard matches.count <= 1 else {
                throw HerdrError.message(L10n.text("Select the exact herdr window in settings; no other window will be changed."))
            }
            if let match = matches.first { selected = match.0; selectedSurface = match.1 }
        }
        let policy = paneID.map { TerminalFocusPolicy.resolve(client: selected, paneID: $0) } ?? .existingAttachment
        return TerminalFocusTarget(client: selected, surface: selectedSurface, policy: policy)
    }

    public static func client(from clients: [TerminalClient], paneID: String?, preferredBundleID: String, preferredClientID: String) throws -> TerminalClient {
        let candidates = clients.filter { preferredBundleID.isEmpty || $0.application.bundleID == preferredBundleID }
        if !preferredClientID.isEmpty {
            guard let selected = candidates.first(where: { $0.id == preferredClientID }) else {
                throw HerdrError.message(L10n.text("The selected herdr window has closed. Select its replacement in settings."))
            }
            return selected
        }
        if let paneID {
            let attached = candidates.filter { $0.attachedPaneID == paneID }
            if attached.count == 1 { return attached[0] }
            if attached.count > 1 { throw HerdrError.message(L10n.text("Select the exact herdr window in settings; no other window will be changed.")) }
        }
        let normal = candidates.filter { $0.attachedPaneID == nil }
        if normal.count == 1 { return normal[0] }
        if candidates.count == 1 { return candidates[0] }
        throw HerdrError.message(L10n.text("Select the exact herdr window in settings; no other window will be changed."))
    }
}
