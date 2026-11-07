import Foundation

public enum AgentHandoff {
    public static let applicationID = "dev.local.dynamicagents"
    public static let helperID = applicationID + ".handoff"
    public static let scheme = "dynamicagents-focus"
    public static let dashboardURL = URL(string: scheme + "://dashboard")!
    public static let requestNotification = Notification.Name(applicationID + ".handoff.request")
    public static let replyNotification = Notification.Name(applicationID + ".handoff.reply")

    public static func url(for agentID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "agent"
        components.queryItems = [URLQueryItem(name: "pane", value: agentID)]
        return components.url!
    }

    public static func agentID(from url: URL) -> String? {
        guard url.absoluteString.utf8.count <= 4096,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme, components.host == "agent",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let query = components.queryItems, query.count == 1,
              query[0].name == "pane", let id = query[0].value,
              !id.isEmpty, id.utf8.count <= 256,
              !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        return id
    }
}
