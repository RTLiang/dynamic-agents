import Foundation

public struct DesktopHookEvent: Decodable, Sendable {
    public let id: String
    public let source: String
    public let status: String
    public let sequence: UInt64
    public let timestamp: TimeInterval
    public let project: String
    public let ancestorPIDs: [Int32]

    public func agent(applications: [TerminalApplication], now: Date) -> Agent? {
        guard id.count == 64, id.allSatisfy(\.isHexDigit), DesktopHookSource(rawValue: source) != nil,
              timestamp.isFinite, timestamp <= now.timeIntervalSince1970 + 5,
              now.timeIntervalSince1970 - timestamp < 86_400, status != "ended" else { return nil }
        let host = ancestorPIDs.lazy.compactMap { pid in applications.first { $0.pid == pid } }.first
        let rawStatus = AgentStatus(serverValue: status)
        let effective = host == nil && rawStatus == .working ? AgentStatus.unknown : rawStatus
        return Agent(hookID: id, kind: source == "copilot" ? "copilot" : source,
                     title: (project.isEmpty ? AgentKind(rawValue: source).displayName : project) + " · " + String(id.prefix(6)),
                     project: project.isEmpty ? AgentKind(rawValue: source).displayName : project,
                     status: effective, sequence: sequence,
                     completedAt: rawStatus == .done ? Date(timeIntervalSince1970: timestamp) : nil,
                     hostBundleID: host?.bundleID, hostName: host?.name)
    }
}

public enum DesktopHookSource: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, cursor, copilot
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .claude: "Claude Code Desktop / CLI"
        case .codex: "Codex App / CLI"
        case .cursor: "Cursor"
        case .copilot: "VS Code Copilot"
        }
    }
}

public enum DesktopHooks {
    public static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["DYNAMIC_AGENTS_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DynamicAgents", isDirectory: true)
    }

    private static var script: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.main.url(forResource: "DynamicAgents_AgentCore", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "desktop-hook", withExtension: "py")
    }

    public static func configure(_ source: DesktopHookSource, action: String) async throws -> Bool {
        guard ["status", "install", "remove"].contains(action), let script else {
            throw HerdrError.message(L10n.text("The desktop hook helper is unavailable. Rebuild the app."))
        }
        let data = try await CommandRunner.run(executable: "/usr/bin/env", arguments: ["python3", script.path, action, source.rawValue])
        struct Result: Decodable { let installed: Bool }
        return try JSONDecoder().decode(Result.self, from: data).installed
    }

    public static func readEvents(in directory: URL = Self.directory) -> [DesktopHookEvent] {
        let folder = directory.appendingPathComponent("events", isDirectory: true)
        let enabledFile = directory.appendingPathComponent("sources.json")
        var enabled: [String: Bool] = [:]
        if FileManager.default.fileExists(atPath: enabledFile.path) {
            guard let data = try? Data(contentsOf: enabledFile), let flags = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [] }
            enabled = flags
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]) else { return [] }
        let recent = files.filter { $0.pathExtension == "json" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        return recent.prefix(1000).compactMap { file in
            guard let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey]),
                  values.isSymbolicLink != true, (values.fileSize ?? .max) < 8192,
                  let data = try? Data(contentsOf: file) else { return nil }
            guard let event = try? JSONDecoder().decode(DesktopHookEvent.self, from: data), enabled[event.source] != false else { return nil }
            return event
        }
    }
}
