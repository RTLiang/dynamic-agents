import Foundation

public struct AgentActivityFeed: Codable, Equatable, Sendable {
    private struct Observation: Codable, Equatable, Sendable {
        var terminalID: String?
        var kind: String?
        var status: AgentStatus
        var completionSequence: UInt64?
        var completedAt: Date?
    }

    public static let completionLifetime: TimeInterval = 10 * 60
    public static let maximumCompletionLifetime: TimeInterval = 24 * 60 * 60
    private var observations: [String: Observation] = [:]
    private var observedAt: Date?

    public init() {}

    @discardableResult
    public mutating func observe(_ agents: [Agent], at now: Date) -> Bool {
        let continuous = observedAt.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 5 } ?? false
        var next: [String: Observation] = [:]
        for agent in agents {
            let legacy = agent.herdrSession != nil ? observations[agent.paneID] : nil
            let previous = (observations[agent.id] ?? legacy).flatMap {
                $0.terminalID == agent.terminalID && $0.kind == agent.kind ? $0 : nil
            }
            var completedAt = previous?.completedAt
            if agent.isHookSession, agent.status == .done, let reported = agent.hookCompletedAt, reported <= now {
                completedAt = reported
            }
            if agent.status == .working || agent.status == .blocked || agent.status == .unknown {
                completedAt = nil
            } else if agent.isHookSession {
                if agent.status != .done { completedAt = nil }
            } else if continuous, let previous {
                let newCompletion = agent.completionSequence != nil && agent.completionSequence != previous.completionSequence
                let enteredDone = agent.completionSequence == nil && agent.status == .done && previous.status != .done
                if newCompletion || enteredDone { completedAt = now }
                if agent.completionSequence == nil && agent.status != .done { completedAt = nil }
            } else if agent.completionSequence != previous?.completionSequence {
                completedAt = nil
            }
            if let completion = completedAt, now.timeIntervalSince(completion) >= Self.maximumCompletionLifetime {
                completedAt = nil
            }
            next[agent.id] = Observation(terminalID: agent.terminalID, kind: agent.kind, status: agent.status,
                                         completionSequence: agent.completionSequence, completedAt: completedAt)
        }
        let changed = next != observations
        observations = next
        observedAt = now
        return changed
    }

    public func agents(from agents: [Agent], at now: Date, completionLifetime: TimeInterval = Self.completionLifetime) -> [Agent] {
        agents.compactMap { agent in
            if agent.status == .working { return agent }
            guard agent.status == .idle || agent.status == .done,
                  let observation = observations[agent.id], observation.terminalID == agent.terminalID,
                  observation.kind == agent.kind, observation.completionSequence == agent.completionSequence,
                  let completedAt = observation.completedAt,
                  now >= completedAt, now.timeIntervalSince(completedAt) < min(max(completionLifetime, 60), Self.maximumCompletionLifetime) else { return nil }
            return agent.withStatus(.done)
        }
    }
}
