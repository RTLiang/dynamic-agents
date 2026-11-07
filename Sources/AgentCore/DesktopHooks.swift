import Foundation

public struct DesktopHookEvent: Decodable, Sendable {
    public let id: String
    public let source: String
    public let status: String
    public let sequence: UInt64
    public let timestamp: TimeInterval
    public let project: String
    public let ancestorPIDs: [Int32]
    public private(set) var title: String?
    public let runtimePID: Int32?
    public let hostBundleIDHint: String?
    public let completedAt: TimeInterval?
    private var completionTime: TimeInterval? {
        guard let value = completedAt ?? (status == "done" ? timestamp : nil), value.isFinite, value >= 0, value <= timestamp else { return nil }
        return value
    }

    public func withTitle(_ value: String?) -> Self {
        var event = self
        event.title = SessionTitle.normalized(value)
        return event
    }

    public func isCurrent(at now: Date) -> Bool {
        id.count == 64 && id.allSatisfy(\.isHexDigit) && DesktopHookSource(rawValue: source) != nil
            && timestamp.isFinite && timestamp <= now.timeIntervalSince1970 + 5
            && now.timeIntervalSince1970 - timestamp < 86_400 && (status != "ended" || completionTime != nil)
            && ancestorPIDs.count <= 40 && ancestorPIDs.allSatisfy { $0 > 1 }
            && Set(ancestorPIDs).count == ancestorPIDs.count
    }

    public func agent(applications: [HostApplication], now: Date, processes: [ProcessRecord] = []) -> Agent? {
        guard isCurrent(at: now) else { return nil }
        let observedHost = HostAppSelection.observed(event: self, applications: applications)
        let resolvedHost = observedHost ?? HostAppSelection.hinted(event: self, applications: applications)
        let live: Bool
        if status == "ended" { live = false }
        else if source == "codex" { live = hasLiveCodex(in: processes, host: observedHost) }
        else if source == "pi" { live = hasLivePi(in: processes, host: observedHost) }
        else {
            live = observedHost != nil || processes.contains { process in
                ancestorPIDs.contains(process.pid)
                    && URL(fileURLWithPath: process.executable).lastPathComponent.lowercased() == (source == "cursor" ? "cursor-agent" : source)
                    && process.startedAt.map { $0.timeIntervalSince1970 <= timestamp } == true
            }
        }
        let host = live ? resolvedHost : nil
        let rawStatus = status == "ended" && completionTime != nil ? AgentStatus.done : AgentStatus(serverValue: status)
        let effective = !live && (rawStatus == .working || rawStatus == .blocked) ? AgentStatus.unknown : rawStatus
        let kind = source == "copilot" ? "copilot" : source
        let kindName = AgentKind(rawValue: kind).displayName
        let displayName: String?
        if source == "codex" {
            if observedHost?.bundleID.lowercased() == "com.openai.codex" { displayName = "Codex App" }
            else if let host { displayName = "Codex CLI · " + host.name }
            else { displayName = "Codex" }
        } else { displayName = nil }
        let displayHost = rawStatus == .done ? resolvedHost : host
        return Agent(hookID: id, kind: kind, title: SessionTitle.normalized(title) ?? kindName + " · " + String(id.prefix(6)),
                     project: project.isEmpty ? L10n.text("Unknown Project") : project,
                     status: effective,
                     completedAt: completionTime.map { Date(timeIntervalSince1970: $0) },
                     hostBundleID: displayHost?.bundleID, hostName: displayHost?.name, displayName: displayName,
                     isSessionAvailable: live)
    }

    private func hasLivePi(in processes: [ProcessRecord], host: HostApplication?) -> Bool {
        guard let runtimePID, ancestorPIDs.contains(runtimePID),
              let runtime = processes.first(where: { $0.pid == runtimePID }),
              let started = runtime.startedAt, started.timeIntervalSince1970 <= timestamp else { return false }
        guard let host else { return true }
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var parent = runtime.parentPID
        var visited = Set<Int32>()
        while parent > 1, visited.insert(parent).inserted {
            if parent == host.pid { return true }
            guard let next = byPID[parent], next.startedAt.map({ $0.timeIntervalSince1970 <= timestamp }) ?? true else { break }
            parent = next.parentPID
        }
        return false
    }

    private func hasLiveCodex(in processes: [ProcessRecord], host: HostApplication?) -> Bool {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        for pid in ancestorPIDs {
            guard let runtime = byPID[pid], URL(fileURLWithPath: runtime.executable).lastPathComponent.lowercased() == "codex",
                  let started = runtime.startedAt, started.timeIntervalSince1970 <= timestamp else { continue }
            guard let host else { return true }
            var parent = runtime.parentPID
            var visited = Set<Int32>()
            while parent > 1, visited.insert(parent).inserted {
                if parent == host.pid { return true }
                guard let next = byPID[parent], next.startedAt.map({ $0.timeIntervalSince1970 <= timestamp }) ?? true else { break }
                parent = next.parentPID
            }
        }
        return false
    }
}

public enum DesktopHookSource: String, CaseIterable, Identifiable, Sendable {
    case pi, claude, codex, cursor, copilot
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .pi: "Pi"
        case .claude: "Claude Code Desktop / CLI"
        case .codex: "Codex App / CLI"
        case .cursor: "Cursor"
        case .copilot: "VS Code Copilot"
        }
    }
}

public struct DesktopHookInstallation: Decodable, Equatable, Sendable {
    public let installed: Bool
    public let current: Bool
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

    public static func installation(_ source: DesktopHookSource) async throws -> DesktopHookInstallation {
        try await request(source, action: "status")
    }

    public static func configure(_ source: DesktopHookSource, action: String) async throws -> Bool {
        try await request(source, action: action).installed
    }

    private static func request(_ source: DesktopHookSource, action: String) async throws -> DesktopHookInstallation {
        guard ["status", "install", "remove"].contains(action), let script else {
            throw AgentError.message(L10n.text("The desktop hook helper is unavailable. Rebuild the app."))
        }
        let data = try await CommandRunner.run(executable: "/usr/bin/env", arguments: ["python3", script.path, action, source.rawValue])
        return try JSONDecoder().decode(DesktopHookInstallation.self, from: data)
    }

    public static func capture(in directory: URL = Self.directory, at now: Date = .now) async -> (events: [DesktopHookEvent], processes: [ProcessRecord]) {
        let reports = readEvents(in: directory).filter { $0.isCurrent(at: now) }
        let codexIDs = Set(reports.filter { $0.source == "codex" }.map(\.id))
        let titles = await CodexSessionTitles.shared.titles(for: codexIDs)
        let events = reports.map { event in
            event.source == "codex" ? event.withTitle(titles[event.id] ?? event.title) : event
        }
        let pids = Set(events.flatMap(\.ancestorPIDs))
        let processes = (try? await ProcessInventory.capture(onlyPIDs: pids)) ?? []
        return (events, processes)
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
