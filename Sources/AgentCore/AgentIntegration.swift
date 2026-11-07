import Foundation

public struct AgentIntegration: Decodable, Identifiable, Equatable, Sendable {
    public let target: String
    public let label: String
    public let command: String
    public let available: Bool
    public let state: State
    public var id: String { target }

    public enum State: String, Sendable, Decodable {
        case notInstalled = "not_installed", current, outdated, unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .unknown
        }

        public var label: String {
            switch self {
            case .notInstalled: L10n.text("Not Installed")
            case .current: L10n.text("Up to Date")
            case .outdated: L10n.text("Update Available")
            case .unknown: L10n.text("Unknown")
            }
        }
    }

    public var reportsLifecycle: Bool {
        ["pi", "omp", "mastracode", "opencode", "kilo", "kimi"].contains(target)
    }

    public var monitoringLabel: String {
        reportsLifecycle ? L10n.text("Lifecycle hooks") : L10n.text("herdr detection")
    }

    public static func decodeList(_ data: Data) throws -> [Self] {
        let response = try JSONDecoder().decode(IntegrationResponse.self, from: data)
        if let error = response.error { throw HerdrError.message(error.message) }
        guard let list = response.result?.integrations else {
            throw HerdrError.message(L10n.text("This herdr server does not provide integration management. Update herdr and try again."))
        }
        return list
    }

    public static func validateMutation(_ data: Data, target: String) throws {
        let response = try JSONDecoder().decode(IntegrationResponse.self, from: data)
        if let error = response.error { throw HerdrError.message(error.message) }
        guard response.result?.target == target else {
            throw HerdrError.message(L10n.text("herdr did not confirm the integration change. Refresh its status before retrying."))
        }
    }
}

private struct IntegrationResponse: Decodable {
    let result: Result?
    let error: APIError?
    struct Result: Decodable {
        let integrations: [AgentIntegration]?
        let target: String?
    }
    struct APIError: Decodable { let message: String }
}

public struct HerdrEndpoint: Decodable, Sendable {
    private let server: Server
    private struct Server: Decodable { let running: Bool; let socket: String }

    public var socketPath: String {
        get throws {
            guard server.running else { throw HerdrError.message(L10n.text("herdr is not connected. Start herdr first.")) }
            guard server.socket.hasPrefix("/"), !server.socket.utf8.contains(0) else {
                throw HerdrError.message(L10n.text("herdr did not return a local socket. Choose a local herdr session."))
            }
            return server.socket
        }
    }
}
