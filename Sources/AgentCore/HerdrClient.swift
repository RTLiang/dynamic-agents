import Foundation
import Darwin

public struct HerdrClient: Sendable {
    public var executable: String
    public var session: String

    public init(executable: String = Self.defaultExecutable, session: String = "") {
        self.executable = executable
        self.session = session
    }
    public static var defaultExecutable: String {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["HERDR_BIN"], "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", NSHomeDirectory() + "/.local/bin/herdr"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/herdr"
    }
    public var sessionName: String { session.isEmpty ? "default" : session }
    private var prefix: [String] { ["--session", sessionName] }
    public func snapshot() async throws -> Snapshot {
        try Snapshot.decode(await CommandRunner.run(executable: executable, arguments: prefix + ["api", "snapshot"]))
    }
    public func integrations() async throws -> [AgentIntegration] {
        try AgentIntegration.decodeList(await integrationRequest(method: "integration.list", target: nil))
    }

    public func changeIntegration(target: String, install: Bool) async throws {
        let response = try await integrationRequest(method: install ? "integration.install" : "integration.uninstall", target: target)
        try AgentIntegration.validateMutation(response, target: target)
    }

    public func socketPath() async throws -> String {
        let status = try await CommandRunner.run(executable: executable, arguments: prefix + ["status", "--json"])
        return try JSONDecoder().decode(HerdrEndpoint.self, from: status).socketPath
    }

    private func integrationRequest(method: String, target: String?) async throws -> Data {
        let path = try await socketPath()
        let request: [String: Any] = ["id": UUID().uuidString, "method": method, "params": target.map { ["target": $0] } ?? [:]]
        let payload = try JSONSerialization.data(withJSONObject: request)
        return try await LocalSocketRequest.send(path: path, payload: payload, timeout: target == nil ? 4 : 15)
    }

}

// One bounded process per poll, with stdout and stderr drained concurrently.
// No shell interpolation; session names and pane IDs remain individual arguments.
public enum CommandRunner {
    public static func run(executable: String, arguments: [String], timeout: TimeInterval = 4) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    guard FileManager.default.isExecutableFile(atPath: executable) else {
                        throw HerdrError.message(L10n.text("herdr was not found. Choose its executable in settings."))
                    }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    var environment = ProcessInfo.processInfo.environment
                    // Finder does not inherit the shell PATH; preserve it and include common install locations.
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
                    process.environment = environment
                    let stdout = Pipe(), stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr
                    process.standardInput = FileHandle.nullDevice
                    let finished = DispatchSemaphore(value: 0)
                    process.terminationHandler = { _ in finished.signal() }
                    try process.run()
                    let output = Drain(), errors = Drain()
                    let readers = DispatchGroup()
                    for (pipe, box) in [(stdout, output), (stderr, errors)] {
                        readers.enter()
                        DispatchQueue.global(qos: .utility).async {
                            box.set(pipe.fileHandleForReading.readDataToEndOfFile())
                            readers.leave()
                        }
                    }
                    let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
                    if timedOut, process.isRunning {
                        // Only kill the child created by this request, never the herdr server.
                        kill(process.processIdentifier, SIGKILL)
                    }
                    process.waitUntilExit()
                    readers.wait()
                    if timedOut { throw HerdrError.message(L10n.text("The herdr connection timed out. Retrying automatically.")) }
                    guard process.terminationStatus == 0 else {
                        let detail = String(data: errors.get(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        throw HerdrError.message(detail.isEmpty ? L10n.text("herdr is not connected. Start herdr first.") : String(detail.prefix(500)))
                    }
                    continuation.resume(returning: output.get())
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private final class Drain: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ value: Data) { lock.lock(); defer { lock.unlock() }; data = value }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
