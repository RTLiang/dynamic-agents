import Foundation
import Testing
@testable import AgentCore

@Test func eachHerdrClientKeepsItsOwnNavigationConfigurationAndCreationTime() {
    let app = TerminalApplication(pid: 10, bundleID: "com.apple.Terminal", name: "Terminal", path: "/System/Applications/Utilities/Terminal.app")
    let firstStart = Date(timeIntervalSince1970: 100)
    let secondStart = Date(timeIntervalSince1970: 200)
    let records = [
        ProcessRecord(pid: 40, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "example"], tty: "/dev/ttys001", configHint: "/tmp/example-one.toml", startedAt: firstStart),
        ProcessRecord(pid: 41, parentPID: 10, executable: "herdr", arguments: ["herdr", "--session", "example"], tty: "/dev/ttys002", configHint: "/tmp/example-two.toml", startedAt: secondStart)
    ]
    let clients = TerminalResolver.resolveClients(processes: records, applications: [app], session: "example")
    #expect(clients.count == 2)
    #expect(clients[0].configPath == "/tmp/example-one.toml")
    #expect(clients[0].startedAt == firstStart)
    #expect(clients[1].configPath == "/tmp/example-two.toml")
    #expect(clients[1].startedAt == secondStart)
}
