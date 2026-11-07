import Foundation
import CryptoKit

public enum AgentStatus: String, CaseIterable, Sendable, Codable {
    case working, blocked, done, idle, unknown

    public init(serverValue: String?) { self = Self(rawValue: serverValue ?? "") ?? .unknown }
    public var priority: Int {
        switch self { case .blocked: 0; case .done: 1; case .working: 2; case .idle: 3; case .unknown: 4 }
    }
    public var label: String {
        switch self { case .blocked: L10n.text("Needs Input"); case .done: L10n.text("Completed"); case .working: L10n.text("Running"); case .idle: L10n.text("Idle"); case .unknown: L10n.text("Unknown") }
    }
}

public struct AgentKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public var displayName: String {
        let key = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "pi": return "Pi"
        case "claude", "claude-code": return "Claude Code"
        case "codex": return "Codex"
        case "gemini": return "Gemini CLI"
        case "cursor", "cursor-agent": return "Cursor Agent"
        case "devin": return "Devin CLI"
        case "agy", "antigravity", "antigravity-cli": return "Antigravity"
        case "cline": return "Cline"
        case "omp": return "OMP"
        case "mastracode": return "MastraCode"
        case "opencode", "opencode2": return "OpenCode"
        case "copilot", "github-copilot": return "GitHub Copilot"
        case "kimi": return "Kimi Code"
        case "kiro", "kiro-cli": return "Kiro CLI"
        case "droid": return "Droid"
        case "amp": return "Amp"
        case "grok": return "Grok CLI"
        case "hermes": return "Hermes Agent"
        case "kilo": return "Kilo Code"
        case "qodercli": return "Qoder CLI"
        case "qwen": return "Qwen Code"
        case "letta": return "Letta Code"
        case "maki": return "Maki"
        case "muse": return "Muse Code"
        case "": return "Agent"
        default: return rawValue
        }
    }
}

public struct Agent: Identifiable, Equatable, Sendable, Decodable {
    public private(set) var id: String
    public let paneID: String
    public private(set) var herdrSession: String?
    public let workspaceID: String
    public let kind: String?
    public private(set) var status: AgentStatus
    public let title: String
    public let cwd: String
    public let name: String?
    public let displayAgent: String?
    public let terminalID: String?
    public let completionSequence: UInt64?
    public let hostBundleID: String?
    public let hookCompletedAt: Date?
    public let isHookSession: Bool
    public var kindName: String {
        if let displayAgent, !displayAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return displayAgent }
        return AgentKind(rawValue: kind ?? "").displayName
    }

    enum CodingKeys: String, CodingKey {
        case id = "pane_id", workspaceID = "workspace_id", kind = "agent"
        case status = "agent_status", title = "terminal_title_stripped", rawTitle = "terminal_title", cwd, name
        case metadataTitle = "title", displayAgent = "display_agent"
        case terminalID = "terminal_id", completionSequence = "completion_seq"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        paneID = id
        herdrSession = nil
        hostBundleID = nil
        hookCompletedAt = nil
        isHookSession = false
        workspaceID = try c.decode(String.self, forKey: .workspaceID)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        status = AgentStatus(serverValue: try c.decodeIfPresent(String.self, forKey: .status))
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        terminalID = try c.decodeIfPresent(String.self, forKey: .terminalID)
        completionSequence = try c.decodeIfPresent(UInt64.self, forKey: .completionSequence)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        displayAgent = try c.decodeIfPresent(String.self, forKey: .displayAgent)
        let metadataTitle = try c.decodeIfPresent(String.self, forKey: .metadataTitle)
        let stripped = try c.decodeIfPresent(String.self, forKey: .title)
        let raw = try c.decodeIfPresent(String.self, forKey: .rawTitle)
        title = [name, metadataTitle, stripped, raw].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? AgentKind(rawValue: kind ?? "").displayName
    }
    public init(hookID: String, kind: String, title: String, project: String, status: AgentStatus,
                sequence: UInt64, completedAt: Date?, hostBundleID: String?, hostName: String? = nil) {
        id = "hook:" + String(hookID.prefix(40))
        paneID = id
        herdrSession = nil
        workspaceID = "desktop:" + project
        self.kind = kind
        self.title = title
        self.status = status
        cwd = ""
        name = nil
        displayAgent = hostName.map { AgentKind(rawValue: kind).displayName + " · " + $0 }
        terminalID = "hook:" + hookID
        completionSequence = status == .done ? sequence : nil
        self.hookCompletedAt = completedAt
        self.hostBundleID = hostBundleID
        isHookSession = true
    }

    public func scoped(to session: String) -> Self {
        guard !isHookSession else { return self }
        var agent = self
        let name = session.isEmpty ? "default" : session
        let digest = SHA256.hash(data: Data(name.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        agent.id = "herdr:" + digest + ":" + paneID
        agent.herdrSession = name
        return agent
    }

    public func withStatus(_ status: AgentStatus) -> Self {
        var agent = self
        agent.status = status
        return agent
    }
}

public struct Workspace: Decodable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
    enum CodingKeys: String, CodingKey { case id = "workspace_id", label }
}

public struct Snapshot: Decodable, Sendable {
    public let agents: [Agent]
    public let workspaces: [Workspace]
    public let version: String
    public let focusedPaneID: String?
    enum CodingKeys: String, CodingKey {
        case agents, workspaces, version
        case focusedPaneID = "focused_pane_id"
    }
    public var trackedAgents: [Agent] {
        agents.filter { !($0.kind?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.sorted {
            if $0.status.priority != $1.status.priority { return $0.status.priority < $1.status.priority }
            if $0.workspaceID != $1.workspaceID { return $0.workspaceID < $1.workspaceID }
            return $0.id < $1.id
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error { throw HerdrError.message(error.message) }
        guard let snapshot = response.result?.snapshot else {
            throw HerdrError.message(L10n.text("herdr returned an unrecognized snapshot. Check its version."))
        }
        return snapshot
    }
    private struct Response: Decodable {
        let result: Result?
        let error: APIError?
        struct Result: Decodable { let snapshot: Snapshot }
        struct APIError: Decodable { let message: String }
    }
}

public enum HerdrError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
