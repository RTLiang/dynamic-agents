import Foundation

public struct HerdrNavigationSnapshot: Decodable, Sendable {
    public struct Space: Decodable, Sendable {
        public let id: String
        public let label: String
        enum CodingKeys: String, CodingKey { case id = "workspace_id", label }
    }
    public struct Tab: Decodable, Sendable {
        public let id: String
        public let workspaceID: String
        public let label: String
        enum CodingKeys: String, CodingKey { case id = "tab_id", workspaceID = "workspace_id", label }
    }
    public struct AgentRow: Decodable, Sendable {
        public let paneID: String
        public let workspaceID: String
        public let tabID: String
        public let kind: String?
        public let displayName: String?
        public let name: String?
        enum CodingKeys: String, CodingKey {
            case paneID = "pane_id", workspaceID = "workspace_id", tabID = "tab_id", kind = "agent", displayName = "display_agent", name
        }
        var label: String { displayName ?? name ?? kind ?? "" }
    }
    public let workspaces: [Space]
    public let tabs: [Tab]
    public let agents: [AgentRow]
    public let focusedPaneID: String?
    enum CodingKeys: String, CodingKey {
        case workspaces, tabs, agents
        case focusedPaneID = "focused_pane_id"
    }

    public static func decode(_ data: Data) throws -> Self {
        struct Envelope: Decodable {
            struct Result: Decodable { let snapshot: HerdrNavigationSnapshot }
            let result: Result?
        }
        guard let result = try JSONDecoder().decode(Envelope.self, from: data).result else {
            throw HerdrError.message(L10n.text("Unable to verify the existing herdr page. Keep its terminal window visible and try again."))
        }
        return result.snapshot
    }

    public static func agentHeader(in screen: String) -> Int? {
        screen.components(separatedBy: .newlines).firstIndex { line in
            let sidebar = leftColumn(line)
            return sidebar == "agents" || sidebar.hasPrefix("agents ")
        }
    }

    public func visibleAgentRow(for paneID: String, screen: String) -> Int? {
        let lines = screen.components(separatedBy: .newlines)
        guard let header = Self.agentHeader(in: screen), agents.contains(where: { $0.paneID == paneID }) else { return nil }
        var matches: [Int] = []
        for row in (header + 1)..<max(header + 1, lines.count - 1) {
            let first = Self.leftColumn(lines[row])
            guard let icon = first.first, !icon.isLetter, !icon.isNumber,
                  first.dropFirst().first?.isWhitespace == true else { continue }
            let location = first.dropFirst().trimmingCharacters(in: .whitespaces).components(separatedBy: " · ")
            guard (1...2).contains(location.count) else { continue }
            let label = Self.leftColumn(lines[row + 1])
            guard !label.isEmpty else { continue }
            let candidates = agents.filter { agent in
                guard let space = workspaces.first(where: { $0.id == agent.workspaceID }),
                      Self.matches(location[0], space.label), Self.matches(label, agent.label) else { return false }
                if location.count == 2 {
                    guard let tab = tabs.first(where: { $0.id == agent.tabID }) else { return false }
                    return Self.matches(location[1], tab.label)
                }
                return true
            }
            if candidates.count == 1, candidates[0].paneID == paneID { matches.append(row) }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func leftColumn(_ line: String) -> String {
        guard let separator = line.firstIndex(of: "│"), line.distance(from: line.startIndex, to: separator) <= 80 else { return "" }
        return line[..<separator].trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ visible: String, _ full: String) -> Bool {
        guard !visible.isEmpty, !full.isEmpty else { return false }
        if visible.hasSuffix("…") {
            let prefix = String(visible.dropLast())
            return prefix.count >= 2 && full.lowercased().hasPrefix(prefix.lowercased())
        }
        return visible.caseInsensitiveCompare(full) == .orderedSame
    }
}

extension HerdrClient {
    public func navigationSnapshot(socketPath: String) async throws -> HerdrNavigationSnapshot {
        let request: [String: Any] = ["id": UUID().uuidString, "method": "session.snapshot", "params": [:] as [String: String]]
        let payload = try JSONSerialization.data(withJSONObject: request)
        return try HerdrNavigationSnapshot.decode(await LocalSocketRequest.send(path: socketPath, payload: payload, timeout: 2))
    }
}
