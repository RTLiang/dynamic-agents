import Foundation

public enum AgentStatus: String, CaseIterable, Sendable, Codable {
    case working, done, idle, unknown

    public init(serverValue: String?) {
        self = serverValue == "blocked" ? .working : Self(rawValue: serverValue ?? "") ?? .unknown
    }
    public init(from decoder: Decoder) throws {
        self.init(serverValue: try decoder.singleValueContainer().decode(String.self))
    }
    public var priority: Int {
        switch self { case .working: 0; case .done: 1; case .idle: 2; case .unknown: 3 }
    }
    public var label: String { label(locale: nil) }
    public func label(locale: Locale?) -> String {
        switch self { case .done: L10n.text("Completed", locale: locale); case .working: L10n.text("Running", locale: locale); case .idle: L10n.text("Idle", locale: locale); case .unknown: L10n.text("Unknown", locale: locale) }
    }
}

public struct AgentKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var displayName: String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pi": "Pi"
        case "claude", "claude-code": "Claude Code"
        case "codex": "Codex"
        case "cursor", "cursor-agent": "Cursor Agent"
        case "copilot", "github-copilot": "GitHub Copilot"
        case "": "Agent"
        default: rawValue
        }
    }
}

public struct Agent: Identifiable, Equatable, Sendable {
    public let id: String
    public let eventID: String
    public let kind: String
    public private(set) var status: AgentStatus
    public let title: String
    public let displayAgent: String?
    public let projectName: String
    public let hostBundleID: String?
    public let completedAt: Date?
    public let isSessionAvailable: Bool
    public var kindName: String { displayAgent ?? AgentKind(rawValue: kind).displayName }

    public init(hookID: String, kind: String, title: String, project: String, status: AgentStatus,
                completedAt: Date?, hostBundleID: String?, hostName: String? = nil, displayName: String? = nil,
                isSessionAvailable: Bool? = nil) {
        id = "hook:" + String(hookID.lowercased().prefix(40))
        eventID = hookID
        self.kind = kind
        self.title = title
        self.status = status
        projectName = project
        displayAgent = displayName ?? hostName.map { AgentKind(rawValue: kind).displayName + " · " + $0 }
        self.completedAt = completedAt
        self.hostBundleID = hostBundleID
        self.isSessionAvailable = isSessionAvailable ?? (hostBundleID != nil)
    }

    public func withStatus(_ status: AgentStatus) -> Self {
        var agent = self
        agent.status = status
        return agent
    }
}

public enum AgentError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
