import Foundation
import Darwin

public struct ProcessRecord: Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let executable: String
    public let arguments: [String]?
    public let tty: String?
    public let sessionHint: String?
    public let socketHint: String?
    public let startedAt: Date?

    public init(pid: Int32, parentPID: Int32, executable: String, arguments: [String]? = nil, tty: String? = nil, sessionHint: String? = nil, socketHint: String? = nil, startedAt: Date? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.executable = executable
        self.arguments = arguments
        self.tty = tty
        self.sessionHint = sessionHint
        self.socketHint = socketHint
        self.startedAt = startedAt
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
    public static func resolve(processes: [ProcessRecord], applications: [TerminalApplication], session: String, socketPath: String? = nil) -> TerminalResolution {
        let clients = resolveClients(processes: processes, applications: applications, session: session, socketPath: socketPath)
        if clients.count == 1 { return .resolved(clients[0].application) }
        let apps = Set(clients.map(\.application)).sorted { ($0.name, $0.pid) < ($1.name, $1.pid) }
        return apps.isEmpty ? .unavailable : .ambiguous(apps)
    }

    public static func resolveClients(processes: [ProcessRecord], applications: [TerminalApplication], session: String, socketPath: String? = nil) -> [TerminalClient] {
        let byPID = processes.reduce(into: [Int32: ProcessRecord]()) { $0[$1.pid] = $1 }
        let appsByPID = applications.reduce(into: [Int32: TerminalApplication]()) { $0[$1.pid] = $1 }
        let targetSession = session.isEmpty ? "default" : session
        var matches: [TerminalClient] = []
        for client in processes {
            guard let invocation = localInvocation(arguments: client.arguments) else { continue }
            let args = Array((client.arguments ?? []).dropFirst())
            let explicit = args.first == "--session" || args.first?.hasPrefix("--session=") == true || args.first == "session"
            if !explicit, let socket = client.socketHint {
                guard socket == socketPath else { continue }
            } else {
                guard (explicit ? invocation.session : client.sessionHint ?? invocation.session) == targetSession else { continue }
            }
            var current = client.parentPID
            var visited = Set<Int32>()
            while current > 1, visited.insert(current).inserted {
                if let app = appsByPID[current] {
                    matches.append(TerminalClient(application: app, processID: client.pid, tty: client.tty, session: targetSession, attachedPaneID: invocation.pane))
                    break
                }
                guard let parent = byPID[current] else { break }
                current = parent.parentPID
            }
        }
        return matches.sorted { $0.processID < $1.processID }
    }

    static func localSession(arguments: [String]?) -> String? { localInvocation(arguments: arguments)?.session }

    private static func localInvocation(arguments: [String]?) -> (session: String, pane: String?)? {
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
        if args.isEmpty { return (session, nil) }
        if args.count == 3, args[0] == "session", args[1] == "attach", !args[2].isEmpty {
            return (args[2], nil)
        }
        if args.count == 3, args[0] == "agent", args[1] == "attach", !args[2].isEmpty {
            return (session, args[2])
        }
        return nil
    }
}

public enum ProcessInventory {
    public static func capture(herdrExecutable: String, onlyPIDs: Set<Int32>? = nil) async throws -> [ProcessRecord] {
        if onlyPIDs?.isEmpty == true { return [] }
        let expected = URL(fileURLWithPath: herdrExecutable).resolvingSymlinksInPath().path
        // proc_pidinfo denies access to root-owned login processes in a terminal's ancestry.
        let output = try await CommandRunner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,uid=,tty="])
        return String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]), let uid = UInt32(fields[2]) else { return nil }
            guard onlyPIDs?.contains(pid) ?? true else { return nil }
            let rawTTY = String(fields[3])
            let tty = rawTTY == "??" || rawTTY == "?" ? nil : (rawTTY.hasPrefix("/dev/") ? rawTTY : "/dev/" + rawTTY)
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathSize = UInt32(path.count)
            let pathResult = proc_pidpath(pid, &path, pathSize)
            let executable = pathResult > 0 ? path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : ""
            let isHerdr = executable == expected || URL(fileURLWithPath: executable).lastPathComponent == "herdr"
            let context = onlyPIDs == nil && isHerdr && uid == getuid() ? readContext(pid: pid) : (nil, nil, nil)
            let start = onlyPIDs != nil && uid == getuid() ? startedAt(pid: pid) : nil
            return ProcessRecord(pid: pid, parentPID: parent, executable: executable, arguments: context.0, tty: tty, sessionHint: context.1, socketHint: context.2, startedAt: start)
        }
    }

    private static func readContext(pid: Int32) -> ([String]?, String?, String?) {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size >= 4, size <= 1_048_576 else { return (nil, nil, nil) }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return (nil, nil, nil) }
        let payload = Array(data.prefix(size))
        let hints = decodeHerdrEnvironment(payload)
        return (decodeArguments(payload), hints["HERDR_SESSION"], hints["HERDR_SOCKET_PATH"])
    }

    public static func startedAt(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    static func decodeHerdrEnvironment(_ bytes: [UInt8]) -> [String: String] {
        guard bytes.count > MemoryLayout<Int32>.size else { return [:] }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard (1...4096).contains(count) else { return [:] }
        var index = MemoryLayout<Int32>.size
        func skipString() { while index < bytes.count && bytes[index] != 0 { index += 1 }; index += 1 }
        skipString()
        while index < bytes.count && bytes[index] == 0 { index += 1 }
        for _ in 0..<count { skipString() }
        var result: [String: String] = [:]
        while index < bytes.count {
            let start = index
            skipString()
            let end = min(index - 1, bytes.count)
            guard end > start else { continue }
            let item = bytes[start..<end]
            for key in ["HERDR_SESSION", "HERDR_SOCKET_PATH"] {
                let prefix = Array((key + "=").utf8)
                if item.starts(with: prefix), item.count - prefix.count <= 4096,
                   let value = String(bytes: item.dropFirst(prefix.count), encoding: .utf8), !value.isEmpty {
                    result[key] = value
                }
            }
        }
        return result
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
