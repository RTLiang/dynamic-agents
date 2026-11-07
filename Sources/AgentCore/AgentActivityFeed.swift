import Foundation

public struct AgentActivityFeed: Sendable {
    public static let completionLifetime: TimeInterval = 10 * 60
    public static let maximumCompletionLifetime: TimeInterval = 24 * 60 * 60
    public init() {}

    public func dashboardAgents(from agents: [Agent], at now: Date, completionLifetime: TimeInterval = Self.completionLifetime) -> [Agent] {
        agents.compactMap { agent in
            if isRecentCompletion(agent, at: now, lifetime: completionLifetime) { return agent.withStatus(.done) }
            guard agent.isSessionAvailable else { return nil }
            return agent.status == .done ? agent.withStatus(.idle) : agent
        }
    }

    public func agents(from agents: [Agent], at now: Date, completionLifetime: TimeInterval = Self.completionLifetime) -> [Agent] {
        dashboardAgents(from: agents, at: now, completionLifetime: completionLifetime).filter { $0.status == .working || $0.status == .done }
    }

    private func isRecentCompletion(_ agent: Agent, at now: Date, lifetime: TimeInterval) -> Bool {
        guard agent.status == .done || agent.status == .idle, let completedAt = agent.completedAt, now >= completedAt else { return false }
        return now.timeIntervalSince(completedAt) < min(max(lifetime, 60), Self.maximumCompletionLifetime)
    }
}
