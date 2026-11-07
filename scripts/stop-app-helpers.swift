import Darwin
import Foundation

struct WidgetProcess {
    let pid: Int32
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}
let arguments = Array(CommandLine.arguments.dropFirst())
let shouldStop = arguments.first == "--stop"
let paths = shouldStop ? Array(arguments.dropFirst()) : arguments
let permittedApps = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path })
let trashPrefix = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true).path + "/"
let inventory = Process()
inventory.executableURL = URL(fileURLWithPath: "/bin/ps")
inventory.arguments = ["-axo", "pid=,uid="]
let output = Pipe()
inventory.standardOutput = output
try inventory.run()
let data = output.fileHandleForReading.readDataToEndOfFile()
inventory.waitUntilExit()
guard inventory.terminationStatus == 0 else { exit(1) }

func identity(_ pid: Int32) -> WidgetProcess? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { return nil }
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let executable = URL(fileURLWithPath: buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
    let identifiers: [String: Set<String>] = ["DynamicAgentsWidgets": ["dev.local.dynamicagents.widgets", "dev.local.dynamicagents.handoff.widgets"], "DynamicAgentsHandoff": ["dev.local.dynamicagents.handoff"]]
    guard let allowed = identifiers[executable.lastPathComponent] else { return nil }
    let helper = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var app = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    if Bundle(url: app)?.bundleIdentifier == "dev.local.dynamicagents.handoff" {
        app = app.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    guard let identifier = Bundle(url: helper)?.bundleIdentifier, allowed.contains(identifier),
          Bundle(url: app)?.bundleIdentifier == "dev.local.dynamicagents",
          permittedApps.contains(app.standardizedFileURL.resolvingSymlinksInPath().path) || app.path.hasPrefix(trashPrefix) else { return nil }
    return WidgetProcess(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
}
func stillMatches(_ process: WidgetProcess) -> Bool {
    guard let current = identity(process.pid) else { return false }
    return current.startSeconds == process.startSeconds && current.startMicroseconds == process.startMicroseconds
}
let processes = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> WidgetProcess? in
    let values = line.split(whereSeparator: \.isWhitespace)
    guard values.count == 2, let pid = Int32(values[0]), let uid = UInt32(values[1]), uid == getuid() else { return nil }
    return identity(pid)
}
if !shouldStop {
    print("Matching owned app helper processes: \(processes.count)")
    exit(0)
}
for process in processes where stillMatches(process) {
    guard kill(process.pid, SIGTERM) == 0 || errno == ESRCH else {
        FileHandle.standardError.write(Data("Unable to stop app helper PID \(process.pid). Installation stopped.\n".utf8))
        exit(1)
    }
}
let deadline = Date.now.addingTimeInterval(5)
while processes.contains(where: stillMatches), Date.now < deadline {
    RunLoop.current.run(until: .now.addingTimeInterval(0.1))
}
guard !processes.contains(where: stillMatches) else {
    FileHandle.standardError.write(Data("An owned app helper process did not stop. Installation stopped.\n".utf8))
    exit(1)
}
print("Stopped \(processes.count) verified app helpers before replacing their bundle")
