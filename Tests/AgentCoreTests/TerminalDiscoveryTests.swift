import AppKit
import Foundation
import Testing
@testable import AgentCore

private let ghostty = TerminalApplication(pid: 10, bundleID: "com.mitchellh.ghostty", name: "Ghostty", path: "/Applications/Ghostty.app")
private let terminal = TerminalApplication(pid: 20, bundleID: "com.apple.Terminal", name: "Terminal", path: "/System/Applications/Utilities/Terminal.app")
private func process(_ pid: Int32, _ parent: Int32, _ args: [String]? = nil) -> ProcessRecord {
    ProcessRecord(pid: pid, parentPID: parent, executable: args == nil ? "/bin/zsh" : "/opt/homebrew/bin/herdr", arguments: args)
}

@Test func followsHerdrAncestryInsteadOfPickingAnotherRunningTerminal() {
    let processes = [process(40, 30, ["herdr"]), process(30, 10)]
    #expect(TerminalResolver.resolve(processes: processes, applications: [terminal, ghostty], session: "") == .resolved(ghostty))
}

@Test func ignoresServersHelpersAndRemoteClients() {
    let commands = [["herdr", "server"], ["herdr", "api", "snapshot"], ["herdr", "agent", "focus", "w1:p1"], ["herdr", "--remote", "host"], ["herdr", "--machine", "other", "agent", "list"], ["herdr", "session", "list"], ["herdr", "--help"]]
    for args in commands {
        #expect(TerminalResolver.resolve(processes: [process(40, 10, args)], applications: [ghostty], session: "") == .unavailable)
    }
}

@Test func matchesNamedSessionAndAttachSyntax() {
    for args in [["herdr", "--session", "research"], ["herdr", "--session=research"], ["herdr", "session", "attach", "research"]] {
        let processes = [process(40, 10, ["herdr"]), process(50, 20, args)]
        #expect(TerminalResolver.resolve(processes: processes, applications: [ghostty, terminal], session: "research") == .resolved(terminal))
        #expect(TerminalResolver.resolve(processes: processes, applications: [ghostty, terminal], session: "default") == .resolved(ghostty))
    }
}

@Test func reportsAmbiguityWithoutGuessingAndPreservesSameAppClients() {
    let sameApp = [process(40, 10, ["herdr"]), process(41, 10, ["herdr"])]
    #expect(TerminalResolver.resolve(processes: sameApp, applications: [ghostty], session: "") == .ambiguous([ghostty]))
    let multiple = sameApp + [process(50, 20, ["herdr"])]
    #expect(TerminalResolver.resolve(processes: multiple, applications: [terminal, ghostty], session: "") == .ambiguous([ghostty, terminal]))
}

@Test func missingAndCyclicParentsDoNotChooseAnUnrelatedApp() {
    for processes in [[process(40, 1, ["herdr"])], [process(40, 99, ["herdr"])], [process(40, 30, ["herdr"]), process(30, 40)]] {
        #expect(TerminalResolver.resolve(processes: processes, applications: [ghostty], session: "") == .unavailable)
    }
}

@Test func argumentDecoderReadsArgvWithoutEnvironment() {
    var argc: Int32 = 3
    var bytes = withUnsafeBytes(of: &argc) { Array($0) }
    bytes += Array("/opt/homebrew/bin/herdr\0\0herdr\0--session\0research notes\0SECRET=do-not-read\0".utf8)
    #expect(ProcessInventory.decodeArguments(bytes) == ["herdr", "--session", "research notes"])
    #expect(ProcessInventory.decodeArguments([1, 0]) == nil)
    #expect(ProcessInventory.decodeArguments(Array(bytes.prefix(8))) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["HERDR_LIVE_TEST"] == "1"))
@MainActor func detectsLiveHerdrTerminalWithoutPreferences() async throws {
    let records = try await Task.detached { try await ProcessInventory.capture(herdrExecutable: HerdrClient.defaultExecutable) }.value
    let apps = NSWorkspace.shared.runningApplications.compactMap { app -> TerminalApplication? in
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
        return TerminalApplication(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? id, path: url.path)
    }
    let socket = try await HerdrClient().socketPath()
    let clients = TerminalResolver.resolveClients(processes: records, applications: apps, session: "", socketPath: socket)
    #expect(!clients.isEmpty)
    #expect(clients.allSatisfy { $0.tty != nil })
}
