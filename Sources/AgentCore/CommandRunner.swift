import Foundation
import Darwin

// One bounded process per poll, with stdout and stderr drained concurrently.
// Arguments are passed without shell interpolation.
public enum CommandRunner {
    public static func run(executable: String, arguments: [String], timeout: TimeInterval = 4) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    guard FileManager.default.isExecutableFile(atPath: executable) else {
                        throw AgentError.message(L10n.text("The hook helper command was not found."))
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
                        // Only terminate the child created by this request.
                        kill(process.processIdentifier, SIGKILL)
                    }
                    process.waitUntilExit()
                    readers.wait()
                    if timedOut { throw AgentError.message(L10n.text("The hook helper command timed out.")) }
                    guard process.terminationStatus == 0 else {
                        let detail = String(data: errors.get(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        throw AgentError.message(detail.isEmpty ? L10n.text("The hook helper command failed.") : String(detail.prefix(500)))
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
