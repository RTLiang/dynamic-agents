import Foundation
import Darwin
import Testing
@testable import AgentCore

private let integrationList = Data("""
{"id":"test","result":{"type":"integration_list","integrations":[
{"target":"pi","label":"Pi","command":"pi","available":true,"state":"current"},
{"target":"codex","label":"Codex","command":"codex","available":true,"state":"not_installed"},
{"target":"future_agent","label":"Future Agent","command":"future","available":false,"state":"future_state"}
]}}
""".utf8)

@Test func integrationListPreservesNewTargetsAndUnknownStates() throws {
    let list = try AgentIntegration.decodeList(integrationList)
    #expect(list.map(\.target) == ["pi", "codex", "future_agent"])
    #expect(list[0].reportsLifecycle && !list[1].reportsLifecycle)
    #expect(list[0].state == .current && list[1].state == .notInstalled && list[2].state == .unknown)
    #expect(!list[2].available)
    #expect(throws: (any Error).self) { try AgentIntegration.decodeList(Data("{\"error\":{\"message\":\"unknown method\"}}".utf8)) }
    #expect(throws: (any Error).self) { try AgentIntegration.decodeList(Data("{\"result\":{}}".utf8)) }
}

@Test func integrationMutationRequiresAcknowledgedTargetAndSurfacesErrors() throws {
    try AgentIntegration.validateMutation(Data("{\"result\":{\"target\":\"codex\"}}".utf8), target: "codex")
    #expect(throws: (any Error).self) {
        try AgentIntegration.validateMutation(Data("{\"result\":{\"target\":\"pi\"}}".utf8), target: "codex")
    }
    #expect(throws: (any Error).self) {
        try AgentIntegration.validateMutation(Data("{\"error\":{\"message\":\"config unavailable\"}}".utf8), target: "codex")
    }
}

@Test func endpointRequiresRunningLocalServer() throws {
    for data in ["{\"server\":{\"running\":false,\"socket\":\"/tmp/example.sock\"}}",
                 "{\"server\":{\"running\":true,\"socket\":\"ssh:example\"}}"] {
        let endpoint = try JSONDecoder().decode(HerdrEndpoint.self, from: Data(data.utf8))
        #expect(throws: (any Error).self) { try endpoint.socketPath }
    }
    let endpoint = try JSONDecoder().decode(HerdrEndpoint.self, from: Data("{\"server\":{\"running\":true,\"socket\":\"/tmp/example.sock\"}}".utf8))
    #expect(try endpoint.socketPath == "/tmp/example.sock")
}

private final class SocketFixture: @unchecked Sendable {
    let path = "/tmp/da-\(UUID().uuidString).sock"
    let descriptor: Int32

    init() throws {
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else { throw POSIXError(.EIO) }
    }

    func serve(reply: Data, delay: useconds_t = 0) -> Task<Data, Never> {
        Task.detached {
            let peer = accept(self.descriptor, nil, nil)
            guard peer >= 0 else { return Data() }
            defer { close(peer) }
            var noSignal: Int32 = 1
            _ = setsockopt(peer, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
            var time = timeval(tv_sec: 3, tv_usec: 0)
            _ = setsockopt(peer, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout.size(ofValue: time)))
            var request = Data(), buffer = [UInt8](repeating: 0, count: 8192)
            while !request.contains(10) {
                let count = recv(peer, &buffer, buffer.count, 0)
                guard count > 0 else { break }
                request.append(contentsOf: buffer.prefix(count))
            }
            if delay > 0 { usleep(delay) }
            for chunk in [reply.prefix(reply.count / 2), reply.suffix(reply.count - reply.count / 2)] {
                _ = chunk.withUnsafeBytes { Darwin.send(peer, $0.baseAddress!, chunk.count, 0) }
            }
            return request
        }
    }

    func cleanup() throws {
        close(descriptor)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["trash", path]
        try process.run()
        process.waitUntilExit()
    }
}

@Test func socketRequestFramesPartialRepliesAndSendsStructuredMutation() async throws {
    let fixture = try SocketFixture()
    defer { try? fixture.cleanup() }
    let line = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: integrationList))
    let server = fixture.serve(reply: line + Data("\nignored next line\n".utf8))
    let payload = Data("{\"id\":\"test\",\"method\":\"integration.install\",\"params\":{\"target\":\"codex\"}}".utf8)
    let result = try await LocalSocketRequest.send(path: fixture.path, payload: payload)
    #expect(try AgentIntegration.decodeList(result) == AgentIntegration.decodeList(integrationList))
    let request = await server.value
    let object = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
    #expect(object["method"] as? String == "integration.install")
    #expect((object["params"] as? [String: String])?["target"] == "codex")
}

@Test func socketRequestTimesOutAndRejectsTruncatedResponse() async throws {
    let delayed = try SocketFixture()
    defer { try? delayed.cleanup() }
    let server = delayed.serve(reply: Data("{}\n".utf8), delay: 200_000)
    let start = Date.now
    await #expect(throws: (any Error).self) {
        try await LocalSocketRequest.send(path: delayed.path, payload: Data("{}".utf8), timeout: 0.05)
    }
    #expect(Date.now.timeIntervalSince(start) < 1)
    _ = await server.value
    let truncated = try SocketFixture()
    defer { try? truncated.cleanup() }
    let other = truncated.serve(reply: Data("{\"result\":".utf8))
    await #expect(throws: (any Error).self) {
        try await LocalSocketRequest.send(path: truncated.path, payload: Data("{}".utf8))
    }
    _ = await other.value
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["HERDR_LIVE_TEST"] == "1"))
func readsRealHerdrIntegrationsWithoutChangingConfiguration() async throws {
    let integrations = try await HerdrClient().integrations()
    #expect(integrations.contains { $0.target == "claude" })
    #expect(integrations.contains { $0.target == "codex" })
    #expect(integrations.contains { $0.target == "pi" })
}
