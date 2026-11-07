import Foundation

public struct AgentHandoffRequest: Codable, Sendable, Equatable {
    public let id: String
    public let agentID: String
    public init(id: String = UUID().uuidString, agentID: String) { self.id = id; self.agentID = agentID }
}

public struct AgentHandoffReply: Codable, Sendable, Equatable {
    public let id: String
    public let error: String
}

public enum AgentHandoff {
    public static let applicationID = "dev.local.dynamicagents"
    public static let scheme = "dynamicagents-focus"
    public static let dashboardURL = URL(string: "dynamicagents://dashboard")!
    public static let requestNotification = Notification.Name(applicationID + ".handoff.request")
    public static let replyNotification = Notification.Name(applicationID + ".handoff.reply")

    public static func requestObject(_ request: AgentHandoffRequest) -> String? {
        guard valid(request.id), agentID(from: url(for: request.agentID)) == request.agentID else { return nil }
        return encode(request)
    }

    public static func request(from object: String) -> AgentHandoffRequest? {
        guard let request: AgentHandoffRequest = decode(object), valid(request.id),
              agentID(from: url(for: request.agentID)) == request.agentID else { return nil }
        return request
    }

    public static func replyObject(id: String, error: String) -> String? {
        guard valid(id) else { return nil }
        return encode(AgentHandoffReply(id: id, error: String(error.prefix(512))))
    }

    public static func reply(from object: String) -> AgentHandoffReply? {
        guard let reply: AgentHandoffReply = decode(object), valid(reply.id), reply.error.utf8.count <= 2048 else { return nil }
        return reply
    }

    private static func valid(_ id: String) -> Bool { UUID(uuidString: id) != nil }
    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        let object = data.base64EncodedString()
        return object.utf8.count <= 4096 ? object : nil
    }
    private static func decode<T: Decodable>(_ object: String) -> T? {
        guard object.utf8.count <= 4096, let data = Data(base64Encoded: object) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func url(for agentID: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "agent"
        components.queryItems = [URLQueryItem(name: "session", value: agentID)]
        return components.url!
    }

    public static func agentID(from url: URL) -> String? {
        guard url.absoluteString.utf8.count <= 4096,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme, components.host == "agent",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let query = components.queryItems, query.count == 1,
              query[0].name == "session", let id = query[0].value,
              id.range(of: "^hook:[0-9a-f]{40}$", options: .regularExpression) != nil,
              !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }) else { return nil }
        return id
    }
}
