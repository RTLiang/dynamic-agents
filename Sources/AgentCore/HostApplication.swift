import Foundation
import Darwin

public struct HostApplication: Identifiable, Hashable, Sendable, Codable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let path: String
    public var id: String { "\(bundleID):\(pid)" }
    public init(pid: Int32, bundleID: String, name: String, path: String) {
        self.pid = pid; self.bundleID = bundleID; self.name = name; self.path = path
    }
}

public struct ProcessRecord: Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let executable: String
    public let startedAt: Date?
    public init(pid: Int32, parentPID: Int32, executable: String, startedAt: Date? = nil) {
        self.pid = pid; self.parentPID = parentPID; self.executable = executable; self.startedAt = startedAt
    }
}

public enum ProcessInventory {
    public static func capture(onlyPIDs: Set<Int32>) async throws -> [ProcessRecord] {
        guard !onlyPIDs.isEmpty else { return [] }
        let output = try await CommandRunner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,uid="])
        return String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), onlyPIDs.contains(pid),
                  let parent = Int32(fields[1]), let uid = UInt32(fields[2]) else { return nil }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let count = proc_pidpath(pid, &path, UInt32(path.count))
            let executable = count > 0 ? path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : ""
            return ProcessRecord(pid: pid, parentPID: parent, executable: executable, startedAt: uid == getuid() ? startedAt(pid: pid) : nil)
        }
    }

    public static func startedAt(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
}

public enum HostAppSelection {
    public static func observed(event: DesktopHookEvent, applications: [HostApplication]) -> HostApplication? {
        event.ancestorPIDs.lazy.compactMap { pid in applications.first { $0.pid == pid } }.first
    }

    public static func hinted(event: DesktopHookEvent, applications: [HostApplication]) -> HostApplication? {
        let allowed: Set<String> = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "com.openai.codex", "com.anthropic.claudefordesktop"]
        guard let hint = event.hostBundleIDHint, allowed.contains(hint) else { return nil }
        let matches = applications.filter { $0.bundleID == hint }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func application(for event: DesktopHookEvent, bundleID: String, applications: [HostApplication], launchDates: [Int32: Date]) -> HostApplication? {
        let eligible = applications.filter { app in launchDates[app.pid].map { $0.timeIntervalSince1970 <= event.timestamp } == true }
        let match = observed(event: event, applications: eligible) ?? hinted(event: event, applications: eligible)
        return match?.bundleID == bundleID ? match : nil
    }
}
