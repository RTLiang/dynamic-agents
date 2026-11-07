import Foundation

public struct TerminalClient: Identifiable, Equatable, Sendable {
    public let application: TerminalApplication
    public let processID: Int32
    public let tty: String?
    public let session: String
    public let attachedPaneID: String?
    public init(application: TerminalApplication, processID: Int32, tty: String?, session: String, attachedPaneID: String?) {
        self.application = application
        self.processID = processID
        self.tty = tty
        self.session = session
        self.attachedPaneID = attachedPaneID
    }

    public var id: String { "\(application.bundleID):\(processID):\(tty ?? "-"):\(session)" }
    public var label: String { "\(application.name) · \(session) · \(tty ?? String(processID))" }
}

public struct TerminalSurface: Equatable, Sendable {
    public let id: String
    public let windowID: String
    public let tty: String
    public let processID: Int32?

    public init(id: String, windowID: String, tty: String, processID: Int32? = nil) {
        self.id = id; self.windowID = windowID; self.tty = tty; self.processID = processID
    }
}

public enum TerminalFocusPolicy: Equatable, Sendable {
    case existingAttachment
    case dedicatedAttachment

    public static func resolve(client: TerminalClient, paneID: String) -> Self {
        if client.attachedPaneID == paneID { return .existingAttachment }
        return .dedicatedAttachment
    }
}

public enum TerminalSurfaceResolver {
    public static func surface(for client: TerminalClient, surfaces: [TerminalSurface]) throws -> TerminalSurface {
        let matches = surfaces.filter { surface in
            if let tty = client.tty { return surface.tty == tty }
            return surface.processID == client.processID
        }
        guard matches.count == 1 else {
            throw HerdrError.message(L10n.text("Unable to identify one terminal window for this herdr client. Refresh and select its window in settings."))
        }
        return matches[0]
    }
}
