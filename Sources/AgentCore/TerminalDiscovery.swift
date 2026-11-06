import Foundation
import Darwin

public struct ProcessRecord: Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let executable: String
    public let arguments: [String]?

    public init(pid: Int32, parentPID: Int32, executable: String, arguments: [String]? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.executable = executable
        self.arguments = arguments
    }
}

public struct TerminalApplication: Identifiable, Hashable, Sendable, Codable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let path: String
    public var id: String { "\(bundleID):\(pid)" }

    public init(pid: Int32, bundleID: String, name: String, path: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

public enum TerminalResolution: Equatable, Sendable {
    case resolved(TerminalApplication)
    case ambiguous([TerminalApplication])
    case unavailable

    public var application: TerminalApplication? {
        if case .resolved(let app) = self { return app }
        return nil
    }
}

public enum TerminalResolver {
    public static func resolve(processes: [ProcessRecord], applications: [TerminalApplication], session: String) -> TerminalResolution {
        let byPID = processes.reduce(into: [Int32: ProcessRecord]()) { $0[$1.pid] = $1 }
        let appsByPID = applications.reduce(into: [Int32: TerminalApplication]()) { $0[$1.pid] = $1 }
        let targetSession = session.isEmpty ? "default" : session
        var matches = Set<TerminalApplication>()
        for client in processes where localSession(arguments: client.arguments) == targetSession {
            var current = client.parentPID
            var visited = Set<Int32>()
            while current > 1, visited.insert(current).inserted {
                if let app = appsByPID[current] {
                    matches.insert(app)
                    break
                }
                guard let parent = byPID[current] else { break }
                current = parent.parentPID
            }
        }
        let sorted = matches.sorted { ($0.name, $0.pid) < ($1.name, $1.pid) }
        if sorted.count == 1 { return .resolved(sorted[0]) }
        return sorted.isEmpty ? .unavailable : .ambiguous(sorted)
    }

    static func localSession(arguments: [String]?) -> String? {
        guard let arguments, !arguments.isEmpty else { return nil }
        var args = Array(arguments.dropFirst())
        var session = "default"
        if args.first == "--session" {
            guard args.count >= 2, !args[1].isEmpty else { return nil }
            session = args[1]
            args.removeFirst(2)
        } else if let first = args.first, first.hasPrefix("--session=") {
            session = String(first.dropFirst("--session=".count))
            guard !session.isEmpty else { return nil }
            args.removeFirst()
        }
        if args.isEmpty { return session }
        if args.count == 3, args[0] == "session", args[1] == "attach", !args[2].isEmpty {
            return args[2]
        }
        return nil
    }
}

public enum ProcessInventory {
    public static func capture(herdrExecutable: String) async throws -> [ProcessRecord] {
        let expected = URL(fileURLWithPath: herdrExecutable).resolvingSymlinksInPath().path
        // proc_pidinfo denies access to root-owned login processes in a terminal's ancestry.
        let output = try await CommandRunner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,uid="])
        return String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]), let uid = UInt32(fields[2]) else { return nil }
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathSize = UInt32(path.count)
            let pathResult = proc_pidpath(pid, &path, pathSize)
            let executable = pathResult > 0 ? path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : ""
            let isHerdr = executable == expected || URL(fileURLWithPath: executable).lastPathComponent == "herdr"
            let arguments = isHerdr && uid == getuid() ? arguments(pid: pid) : nil
            return ProcessRecord(pid: pid, parentPID: parent, executable: executable, arguments: arguments)
        }
    }

    private static func arguments(pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size >= 4, size <= 1_048_576 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return nil }
        return decodeArguments(Array(data.prefix(size)))
    }

    static func decodeArguments(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc <= 4096 else { return nil }
        var cursor = MemoryLayout<Int32>.size
        while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
        while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }
        var result: [String] = []
        for _ in 0..<argc {
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
            guard cursor < bytes.count else { return nil }
            result.append(String(decoding: bytes[start..<cursor], as: UTF8.self))
            cursor += 1
        }
        return result
    }
}
