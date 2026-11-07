import Foundation
import Testing
@testable import AgentCore

private let clientApp = TerminalApplication(pid: 10, bundleID: "com.mitchellh.ghostty", name: "Ghostty", path: "/Applications/Ghostty.app")

@Test func keepsWindowsOfOneTerminalAppDistinctAndScopesAttachments() {
    let records = [
        ProcessRecord(pid: 40, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "research"], tty: "/dev/ttys001"),
        ProcessRecord(pid: 41, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "research"], tty: "/dev/ttys002"),
        ProcessRecord(pid: 42, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "other", "agent", "attach", "wA:p1"], tty: "/dev/ttys003"),
        ProcessRecord(pid: 43, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "research", "agent", "attach", "wA:p1"], tty: "/dev/ttys004")
    ]
    let clients = TerminalResolver.resolveClients(processes: records, applications: [clientApp], session: "research")
    #expect(clients.count == 3)
    #expect(Set(clients.map(\.id)).count == 3)
    #expect(clients.last?.attachedPaneID == "wA:p1")
    #expect(clients.allSatisfy { $0.session == "research" })
}

@Test func inheritedEndpointsNeverMasqueradeAsTheDefaultSession() {
    let inherited = ProcessRecord(pid: 40, parentPID: 10, executable: "herdr", arguments: ["herdr"], tty: "/dev/ttys001", sessionHint: "research")
    #expect(TerminalResolver.resolveClients(processes: [inherited], applications: [clientApp], session: "").isEmpty)
    #expect(TerminalResolver.resolveClients(processes: [inherited], applications: [clientApp], session: "research").count == 1)
    let socket = ProcessRecord(pid: 41, parentPID: 10, executable: "herdr", arguments: ["herdr"], socketHint: "/tmp/example-endpoint.sock")
    #expect(TerminalResolver.resolveClients(processes: [socket], applications: [clientApp], session: "").isEmpty)
    #expect(TerminalResolver.resolveClients(processes: [socket], applications: [clientApp], session: "", socketPath: "/tmp/example-endpoint.sock").count == 1)
    let explicit = ProcessRecord(pid: 42, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "default"], sessionHint: "research", socketHint: "/tmp/other-endpoint.sock")
    #expect(TerminalResolver.resolveClients(processes: [explicit], applications: [clientApp], session: "").count == 1)
}

@Test func onlyReadsHerdrEndpointHintsFromTheEnvironment() {
    var argc: Int32 = 1
    var bytes = withUnsafeBytes(of: &argc) { Array($0) }
    bytes += Array("/bin/herdr\0\0herdr\0SECRET=must-not-escape\0HERDR_SESSION=research\0HERDR_SOCKET_PATH=/tmp/example-endpoint.sock\0OTHER=private\0".utf8)
    #expect(ProcessInventory.decodeHerdrEnvironment(bytes) == ["HERDR_SESSION": "research", "HERDR_SOCKET_PATH": "/tmp/example-endpoint.sock"])
    #expect(ProcessInventory.decodeArguments(bytes) == ["herdr"])
    #expect(ProcessInventory.decodeHerdrEnvironment([1, 0]).isEmpty)
}

@Test func surfaceResolutionUsesTTYAndNeverTheFirstWindow() throws {
    let client = TerminalClient(application: clientApp, processID: 40, tty: "/dev/ttys002", session: "default", attachedPaneID: nil)
    let wrong = TerminalSurface(id: "first", windowID: "window-one", tty: "/dev/ttys001", processID: 40)
    let correct = TerminalSurface(id: "second", windowID: "window-two", tty: "/dev/ttys002", processID: 41)
    #expect(try TerminalSurfaceResolver.surface(for: client, surfaces: [wrong, correct]) == correct)
    #expect(throws: HerdrError.self) { try TerminalSurfaceResolver.surface(for: client, surfaces: [wrong]) }
    #expect(throws: HerdrError.self) { try TerminalSurfaceResolver.surface(for: client, surfaces: [correct, correct]) }
}

@Test func navigationReusesAttachmentsAndNeverBroadcastsServerFocus() {
    let normal = TerminalClient(application: clientApp, processID: 40, tty: "/dev/ttys001", session: "default", attachedPaneID: nil)
    let attached = TerminalClient(application: clientApp, processID: 41, tty: "/dev/ttys002", session: "default", attachedPaneID: "wA:p1")
    #expect(TerminalFocusPolicy.resolve(client: normal, paneID: "wA:p1") == .dedicatedAttachment)
    #expect(TerminalFocusPolicy.resolve(client: attached, paneID: "wA:p1") == .existingAttachment)
    #expect(TerminalFocusPolicy.resolve(client: attached, paneID: "wA:p2") == .dedicatedAttachment)
}

@Test func activityIDsCannotJumpIntoADifferentSession() throws {
    let agent = try JSONDecoder().decode(Agent.self, from: Data(#"{"pane_id":"wA:p1","workspace_id":"wA","agent":"pi","agent_status":"working","terminal_id":"term-1"}"#.utf8))
    let research = agent.scoped(to: "research")
    let other = agent.scoped(to: "other")
    #expect(research.id != other.id)
    #expect(research.paneID == other.paneID)
    #expect(research.herdrSession == "research")
    #expect(research.id.count <= 64)
    #expect(agent.scoped(to: "").id == agent.scoped(to: "default").id)
    var feed = AgentActivityFeed()
    feed.observe([agent], at: Date(timeIntervalSince1970: 100))
    feed.observe([agent.withStatus(.done)], at: Date(timeIntervalSince1970: 101))
    #expect(feed.agents(from: [agent.withStatus(.done)], at: Date(timeIntervalSince1970: 102)).count == 1)
    feed.observe([research.withStatus(.done)], at: Date(timeIntervalSince1970: 102))
    #expect(feed.agents(from: [research.withStatus(.done)], at: Date(timeIntervalSince1970: 102)).count == 1)
    feed.observe([other.withStatus(.done)], at: Date(timeIntervalSince1970: 103))
    #expect(feed.agents(from: [other.withStatus(.done)], at: Date(timeIntervalSince1970: 103)).isEmpty)
}
