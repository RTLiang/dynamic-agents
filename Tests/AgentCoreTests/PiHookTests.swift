import Foundation
import Testing
@testable import AgentCore

private func piEvent(hint: String = "com.mitchellh.ghostty") throws -> DesktopHookEvent {
    try JSONDecoder().decode(DesktopHookEvent.self, from: JSONSerialization.data(withJSONObject: [
        "id": String(repeating: "a", count: 64), "source": "pi", "status": "working", "sequence": 1,
        "timestamp": 1000, "project": "Example", "title": "Named Pi session", "ancestorPIDs": [51, 52, 50], "runtimePID": 51, "hostBundleIDHint": hint
    ]))
}
@Test func piSessionRequiresItsObservedRuntimeToReachTheHost() throws {
    let event = try piEvent()
    let host = HostApplication(pid: 50, bundleID: "example.host", name: "Example", path: "/Applications/Example.app")
    let parents = [ProcessRecord(pid: 52, parentPID: 50, executable: "/usr/bin/login")]
    let valid = parents + [ProcessRecord(pid: 51, parentPID: 52, executable: "/usr/local/bin/node", startedAt: .distantPast)]
    let agent = try #require(event.agent(applications: [host], now: Date(timeIntervalSince1970: 1001), processes: valid))
    #expect(agent.status == .working && agent.isSessionAvailable && agent.hostBundleID == host.bundleID)
    #expect(agent.title == "Named Pi session")
    for runtime in [ProcessRecord(pid: 51, parentPID: 1, executable: "/usr/local/bin/node", startedAt: .distantPast),
                    ProcessRecord(pid: 51, parentPID: 52, executable: "/usr/local/bin/node", startedAt: Date(timeIntervalSince1970: 1100)),
                    ProcessRecord(pid: 51, parentPID: 52, executable: "/usr/local/bin/node")] {
        #expect(event.agent(applications: [host], now: Date(timeIntervalSince1970: 1001), processes: parents + [runtime])?.status == .unknown)
    }
    #expect(event.agent(applications: [host], now: Date(timeIntervalSince1970: 1001), processes: [])?.isSessionAvailable == false)
}

@Test func detachedPiRuntimeCanUseAKnownAppHintWithoutWindowRouting() throws {
    let event = try piEvent()
    let host = HostApplication(pid: 80, bundleID: "com.mitchellh.ghostty", name: "Example", path: "/Applications/Example.app")
    let runtime = ProcessRecord(pid: 51, parentPID: 52, executable: "/usr/bin/node", startedAt: .distantPast)
    let now = Date(timeIntervalSince1970: 1001)
    let agent = try #require(event.agent(applications: [host], now: now, processes: [runtime]))
    #expect(agent.status == .working && agent.hostBundleID == host.bundleID)
    #expect(event.agent(applications: [], now: now, processes: [runtime])?.isSessionAvailable == true)
    #expect(HostAppSelection.application(for: event, bundleID: host.bundleID, applications: [host], launchDates: [80: .distantPast]) == host)
    #expect(HostAppSelection.application(for: event, bundleID: host.bundleID, applications: [host], launchDates: [80: Date(timeIntervalSince1970: 1100)]) == nil)
    let duplicate = HostApplication(pid: 81, bundleID: host.bundleID, name: host.name, path: host.path)
    #expect(event.agent(applications: [host, duplicate], now: now, processes: [runtime])?.hostBundleID == nil)
    let arbitrary = try piEvent(hint: "unrecognized.app")
    let unrecognized = HostApplication(pid: 82, bundleID: "unrecognized.app", name: "Example", path: "/Applications/Example.app")
    #expect(arbitrary.agent(applications: [unrecognized], now: now, processes: [runtime])?.hostBundleID == nil)
    #expect(event.agent(applications: [host], now: now, processes: [])?.status == .unknown)
}
