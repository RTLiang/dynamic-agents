import Foundation

public struct AgentActivityServiceRequest: Codable, Sendable {
    public let id: String
    public let action: String
    public let state: AgentActivityState?
    public let session: String
    public let forceUpdate: Bool?
    public init(id: String = UUID().uuidString, action: String, state: AgentActivityState? = nil, session: String = "", forceUpdate: Bool = false) {
        self.id = id; self.action = action; self.state = state; self.session = session; self.forceUpdate = forceUpdate
    }
    public static let notification = Notification.Name("dev.local.dynamicagents.activity.request")
}

public struct AgentActivityServiceReply: Codable, Sendable {
    public let id: String
    public let enabled: Bool
    public let running: Bool
    public let authorized: Bool
    public let activityID: String?
    public let activeCount: Int
    public let state: AgentActivityState?
    public let staleDate: Date?
    public let message: String?
    public init(id: String, enabled: Bool, running: Bool, authorized: Bool, activityID: String?, activeCount: Int, state: AgentActivityState?, staleDate: Date?, message: String?) {
        self.id = id; self.enabled = enabled; self.running = running; self.authorized = authorized
        self.activityID = activityID; self.activeCount = activeCount; self.state = state; self.staleDate = staleDate; self.message = message
    }
    public static let notification = Notification.Name("dev.local.dynamicagents.activity.reply")
}
