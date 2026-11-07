import CryptoKit
import Foundation
import Testing
@testable import AgentCore

private func hookID(_ id: String) -> String {
    SHA256.hash(data: Data(("codex:" + id).utf8)).map { String(format: "%02x", $0) }.joined()
}
private func entry(_ id: String, _ title: String) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: ["id": id, "thread_name": title, "updated_at": "2026-01-01T00:00:00Z"])
    data.append(10)
    return data
}
private func fixture(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-titles-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["trash", root.path]
        try? process.run()
        process.waitUntilExit()
    }
    try await body(root.appendingPathComponent("session_index.jsonl"))
}

@Test func codexTitlesMatchOnlyTheRequestedSessionHashesAndUseTheLatestName() async throws {
    try await fixture { url in
        let data = try entry("thread-one", "Original name") + Data("broken row\n".utf8)
            + entry("thread-two", "Unrelated title") + entry("thread-one", "Rename settings")
            + Data("{\"id\":\"partial".utf8)
        try data.write(to: url)
        let names = await CodexSessionTitles().titles(for: [hookID("thread-one")], in: url)
        #expect(names == [hookID("thread-one"): "Rename settings"])
    }
}

@Test func codexTitleCacheRefreshesAfterRenameAndWhenRequestedSessionsChange() async throws {
    try await fixture { url in
        try entry("thread-one", "First name").write(to: url)
        let reader = CodexSessionTitles()
        let before = await reader.titles(for: [hookID("thread-one")], in: url)
        #expect(before[hookID("thread-one")] == "First name")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: entry("thread-one", "Current name") + entry("thread-two", "Second task"))
        try handle.close()
        let renamed = await reader.titles(for: [hookID("thread-one")], in: url)
        #expect(renamed[hookID("thread-one")] == "Current name")
        let second = await reader.titles(for: [hookID("thread-two")], in: url)
        #expect(second == [hookID("thread-two"): "Second task"])
    }
}

@Test func codexTitleReaderFallsBackForMissingSymlinkedOrOversizedIndexes() async throws {
    try await fixture { url in
        let reader = CodexSessionTitles()
        let missing = await reader.titles(for: [hookID("one")], in: url)
        #expect(missing.isEmpty)
        try entry("one", "Example title").write(to: url)
        let link = url.deletingLastPathComponent().appendingPathComponent("linked.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let linked = await reader.titles(for: [hookID("one")], in: link)
        #expect(linked.isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 17 * 1024 * 1024)
        try handle.close()
        let oversized = await reader.titles(for: [hookID("one")], in: url)
        #expect(oversized.isEmpty)
    }
}

@Test func emptyLatestCodexTitleClearsTheEarlierName() async throws {
    try await fixture { url in
        try (entry("one", "Earlier title") + entry("one", " \n\t ")).write(to: url)
        let names = await CodexSessionTitles().titles(for: [hookID("one")], in: url)
        #expect(names.isEmpty)
    }
}

@Test func sessionTitlesChangePresentationWithoutChangingSessionIdentityOrState() throws {
    let json: [String: Any] = ["id": hookID("one"), "source": "codex", "status": "done", "sequence": 1,
                               "timestamp": Date.now.timeIntervalSince1970, "project": "Example", "ancestorPIDs": []]
    let event = try JSONDecoder().decode(DesktopHookEvent.self, from: JSONSerialization.data(withJSONObject: json))
    let original = try #require(event.agent(applications: [], now: .now))
    let titledEvent = event.withTitle("  Fix\n settings\t layout  ")
    let titled = try #require(titledEvent.agent(applications: [], now: .now))
    #expect(titled.title == "Fix settings layout")
    #expect(titled.id == original.id && titled.status == original.status)
    #expect(titled.hookCompletedAt == original.hookCompletedAt)
    #expect(titled.projectName == "Example")
    #expect(event.withTitle("\n ").agent(applications: [], now: .now)?.title == original.title)
    #expect(SessionTitle.normalized(String(repeating: "字", count: 500))?.count == 240)
    let activity = AgentActivityState(agents: [titled], workspaces: [])
    #expect(activity.items.first?.title == "Fix settings layout")
}
