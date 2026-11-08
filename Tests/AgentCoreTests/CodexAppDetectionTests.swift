import Foundation
import Testing
@testable import AgentCore

private let codexApp = HostApplication(pid: 50, bundleID: "com.openai.codex", name: "ChatGPT", path: "/Applications/Example.app")
private let liveCodex = ProcessRecord(pid: 51, parentPID: 50, executable: "/usr/local/bin/codex", startedAt: .distantPast)
private func codexEvent(status: String = "working", project: String = "a", ancestors: [Int32] = [51, 50]) throws -> DesktopHookEvent {
    let data: [String: Any] = ["id": String(repeating: "a", count: 64), "source": "codex", "codexSessionKind": "user", "status": status,
                               "sequence": 1234, "timestamp": Date.now.timeIntervalSince1970,
                               "project": project, "ancestorPIDs": ancestors]
    return try JSONDecoder().decode(DesktopHookEvent.self, from: JSONSerialization.data(withJSONObject: data))
}

@Test func codexAppIdentityDoesNotDependOnItsLocalizedDisplayName() throws {
    let event = try codexEvent()
    let result = event.agent(applications: [codexApp], now: .now, processes: [liveCodex])
    let agent = try #require(result)
    #expect(agent.kindName == "Codex App")
    #expect(agent.hostBundleID == "com.openai.codex")
    #expect(agent.title == "Codex · aaaaaa")
    #expect(agent.projectName == "a")
    #expect(agent.status == .working)
}

@Test func codexAppPresenceWithoutARuntimeDoesNotEstablishWorkingOrBlockedState() throws {
    for status in ["working", "blocked"] {
        let event = try codexEvent(status: status)
        let agent = event.agent(applications: [codexApp], now: .now)
        #expect(agent?.status == .unknown)
        #expect(agent?.hostBundleID == nil)
        #expect(agent?.kindName == "Codex App")
    }
}

@Test func codexAppRejectsReusedPIDsWrongExecutablesAndReparentedWorkers() throws {
    let event = try codexEvent()
    let invalid = [
        ProcessRecord(pid: 51, parentPID: 50, executable: "/usr/local/bin/codex", startedAt: Date(timeIntervalSince1970: event.timestamp + 1)),
        ProcessRecord(pid: 51, parentPID: 50, executable: "/usr/bin/sleep", startedAt: .distantPast),
        ProcessRecord(pid: 51, parentPID: 1, executable: "/usr/local/bin/codex", startedAt: .distantPast),
        ProcessRecord(pid: 51, parentPID: 50, executable: "/usr/local/bin/codex")
    ]
    for runtime in invalid {
        let agent = event.agent(applications: [codexApp], now: .now, processes: [runtime])
        #expect(agent?.status == .unknown)
        #expect(agent?.hostBundleID == nil)
    }
}

@Test func codexCLIAndChatGPTAreNotClassifiedAsTheCodexApp() throws {
    let event = try codexEvent()
    for app in [
        HostApplication(pid: 50, bundleID: "com.mitchellh.ghostty", name: "Ghostty", path: "/Applications/Ghostty.app"),
        HostApplication(pid: 50, bundleID: "com.openai.chat", name: "ChatGPT", path: "/Applications/Example.app")
    ] {
        let agent = event.agent(applications: [app], now: .now, processes: [liveCodex])
        #expect(agent?.kindName == "Codex CLI · " + app.name)
        #expect(agent?.status == .working)
    }
}

@Test func codexRuntimeResolutionAllowsExpiredHookShellsAndRootOwnedLoginAncestors() throws {
    let event = try codexEvent(ancestors: [54, 51, 52, 50])
    let records = [
        ProcessRecord(pid: 51, parentPID: 52, executable: "/usr/local/bin/codex", startedAt: .distantPast),
        ProcessRecord(pid: 52, parentPID: 50, executable: "/usr/bin/login")
    ]
    #expect(event.agent(applications: [codexApp], now: .now, processes: records)?.status == .working)
}

@Test func codexCompletionRemainsHistoricalAfterItsRuntimeExits() throws {
    let event = try codexEvent(status: "done")
    let result = event.agent(applications: [], now: .now)
    let agent = try #require(result)
    let feed = AgentActivityFeed()
    #expect(agent.status == .done)
    #expect(agent.hostBundleID == nil)
    #expect(feed.agents(from: [agent], at: .now).count == 1)
}

@Test func missingCodexProjectMetadataDoesNotInventAProjectFromTheAgentName() throws {
    let event = try codexEvent(project: "")
    let agent = event.agent(applications: [codexApp], now: .now, processes: [liveCodex])
    #expect(agent?.projectName == L10n.text("Unknown Project"))
    #expect(agent?.title == "Codex · aaaaaa")
}
