import Foundation
import Testing
@testable import AgentCore

@Test func commandRunnerPreservesArgumentsWithoutShellExpansion() async throws {
    let output = try await CommandRunner.run(executable: "/usr/bin/printf", arguments: ["%s", "$(whoami); value with spaces"])
    #expect(String(decoding: output, as: UTF8.self) == "$(whoami); value with spaces")
}
@Test func commandRunnerReportsMissingBinaryAndNonzeroExit() async {
    await #expect(throws: (any Error).self) { try await CommandRunner.run(executable: "/no-such-hook-helper", arguments: []) }
    await #expect(throws: (any Error).self) { try await CommandRunner.run(executable: "/usr/bin/false", arguments: []) }
}
@Test func commandRunnerTimesOutOnlyItsOwnChild() async {
    let start = Date.now
    await #expect(throws: (any Error).self) { try await CommandRunner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.1) }
    #expect(Date.now.timeIntervalSince(start) < 2)
}
