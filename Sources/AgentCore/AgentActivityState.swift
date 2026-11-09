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
    public var done: Int
    public var total: Int
    public var connected: Bool
    public var items: [Item]
    public var languageIdentifier: String?
    public var locale: Locale { Locale(identifier: languageIdentifier ?? L10n.preferredLanguage) }
    public var headline: String {
        if !connected { return L10n.text("Hook monitoring unavailable") }
        if working > 0 { return L10n.format("agent.running", Int64(working)) }
        if done > 0 { return L10n.format("agent.completed", Int64(done)) }
        return total > 0 ? L10n.text("All agents are ready") : L10n.text("Waiting for agents")
    }
    public func compactLabels(locale: Locale? = nil, accessibility: Bool = false) -> [String] {
        let locale = locale ?? self.locale
        guard connected else { return [L10n.text("Offline", locale: locale)] }
        return [(working, accessibility ? "%@ working" : "%@ Work"), (done, accessibility ? "%@ completed" : "%@ Done")].compactMap { count, key in
            guard count > 0 else { return nil }
            return L10n.format(key, count > 99 ? "99+" : String(count), locale: locale)
        }
    }

    public var prominentCount: Int {
        if working > 0 { return working }
        if done > 0 { return done }
        return total
    }
    public var status: AgentStatus {
        if !connected { return .unknown }
        if working > 0 { return .working }
        if done > 0 { return .done }
        return .idle
    }
    public init(agents: [Agent], connected: Bool = true, prioritizeRunning: Bool = false, itemLimit: Int = 3,
                languageIdentifier: String? = L10n.preferredLanguage) {
        self.languageIdentifier = languageIdentifier
        self.connected = connected
        working = agents.filter { $0.status == .working }.count
        done = agents.filter { $0.status == .done }.count
        total = agents.count
        let ordered = agents.sorted {
            if prioritizeRunning, ($0.status == .working) != ($1.status == .working) { return $0.status == .working }
            if $0.status.priority != $1.status.priority { return $0.status.priority < $1.status.priority }
            return $0.id < $1.id
        }
        items = []
        var remaining = 3600
        for agent in ordered.prefix(max(0, itemLimit)) {
            let item = Item(id: Self.bounded(agent.id, bytes: 64), title: Self.bounded(agent.title, bytes: 320),
                            kind: Self.bounded(agent.kind, bytes: 48), status: agent.status,
                            project: Self.bounded(agent.projectName, bytes: 100),
                            displayAgent: Self.bounded(agent.kindName, bytes: 100))
            guard let encoded = try? JSONEncoder().encode(item), encoded.count + 1 <= remaining else { break }
            items.append(item)
            remaining -= encoded.count + 1
        }
    }
    private enum CodingKeys: String, CodingKey {
        case working, done, total, connected, items, languageIdentifier
    }
    private enum LegacyKeys: String, CodingKey { case blocked }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let running = max(0, try values.decode(Int.self, forKey: .working))
        let previous = max(0, try legacy.decodeIfPresent(Int.self, forKey: .blocked) ?? 0)
        let (sum, overflow) = running.addingReportingOverflow(previous)
        working = overflow ? Int.max : sum
        done = try values.decode(Int.self, forKey: .done)
        total = try values.decode(Int.self, forKey: .total)
        connected = try values.decode(Bool.self, forKey: .connected)
        items = try values.decode([Item].self, forKey: .items)
        languageIdentifier = try values.decodeIfPresent(String.self, forKey: .languageIdentifier)
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
