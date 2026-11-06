import Foundation

/// A small, bounded payload shared with the Widget extension (well below ActivityKit's 4 KB limit).
public struct AgentActivityState: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var kind: String
        public var status: AgentStatus
        public var project: String
        public var displayAgent: String?
        public var kindName: String { displayAgent ?? AgentKind(rawValue: kind).displayName }
    }
    public var working: Int
    public var blocked: Int
    public var done: Int
    public var total: Int
    public var connected: Bool
    public var items: [Item]
    public var headline: String {
        if !connected { return L10n.text("herdr connection lost") }
        if blocked > 0 { return L10n.format("agent.waiting", Int64(blocked)) }
        if done > 0 { return L10n.format("agent.completed", Int64(done)) }
        if working > 0 { return L10n.format("agent.running", Int64(working)) }
        return total > 0 ? L10n.text("All agents are ready") : L10n.text("Waiting for agents")
    }
    public func compactLabels(locale: Locale? = nil, accessibility: Bool = false) -> [String] {
        guard connected else { return [L10n.text("Offline", locale: locale)] }
        return [(working, accessibility ? "%@ running" : "%@ Run"), (done, accessibility ? "%@ completed" : "%@ Done")].compactMap { count, key in
            guard count > 0 else { return nil }
            return L10n.format(key, count > 99 ? "99+" : String(count), locale: locale)
        }
    }

    public var prominentCount: Int {
        if blocked > 0 { return blocked }
        if done > 0 { return done }
        if working > 0 { return working }
        return total
    }
    public var status: AgentStatus {
        if !connected { return .unknown }
        if blocked > 0 { return .blocked }
        if done > 0 { return .done }
        if working > 0 { return .working }
        return .idle
    }
    public init(agents: [Agent], workspaces: [Workspace], connected: Bool = true, prioritizeRunning: Bool = false, itemLimit: Int = 3) {
        self.connected = connected
        working = agents.filter { $0.status == .working }.count
        blocked = agents.filter { $0.status == .blocked }.count
        done = agents.filter { $0.status == .done }.count
        total = agents.count
        let names = workspaces.reduce(into: [String: String]()) { $0[$1.id] = $1.label }
        let ordered = agents.sorted {
            if prioritizeRunning, ($0.status == .working) != ($1.status == .working) { return $0.status == .working }
            if $0.status.priority != $1.status.priority { return $0.status.priority < $1.status.priority }
            return $0.id < $1.id
        }
        items = []
        var remaining = 3600
        for agent in ordered.prefix(max(0, itemLimit)) {
            let item = Item(id: Self.bounded(agent.id, bytes: 64), title: Self.bounded(agent.title, bytes: 320),
                            kind: Self.bounded(agent.kind ?? "agent", bytes: 48), status: agent.status,
                            project: Self.bounded(names[agent.workspaceID] ?? agent.workspaceID, bytes: 100),
                            displayAgent: Self.bounded(agent.kindName, bytes: 100))
            guard let encoded = try? JSONEncoder().encode(item), encoded.count + 1 <= remaining else { break }
            items.append(item)
            remaining -= encoded.count + 1
        }
    }
    private static func bounded(_ text: String, bytes: Int) -> String {
        // Bound UTF-8 rather than grapheme count: one composed character can contain
        // thousands of combining scalars. Strip controls, which JSON otherwise escapes.
        var result = ""
        var remaining = bytes
        for scalar in text.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { continue }
            let cost = scalar.utf8.count
            guard cost <= remaining else { break }
            result.unicodeScalars.append(scalar)
            remaining -= cost
        }
        return result
    }
}
