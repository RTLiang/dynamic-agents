import CryptoKit
import Foundation

public enum SessionTitle {
    public static func normalized(_ title: String?) -> String? {
        guard let title else { return nil }
        let printable = title.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        let text = printable.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(240))
    }
}

public actor CodexSessionTitles {
    public static let shared = CodexSessionTitles()
    public static var indexURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let root: URL
        if let isolated = environment["DYNAMIC_AGENTS_CONFIG_HOME"], !isolated.isEmpty {
            root = URL(fileURLWithPath: isolated, isDirectory: true).appendingPathComponent(".codex", isDirectory: true)
        } else if let override = environment["CODEX_HOME"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }
        return root.appendingPathComponent("session_index.jsonl")
    }

    private struct Stamp: Equatable {
        let url: URL
        let size: Int
        let modified: Date
        let inode: UInt64
        let requested: Set<String>
    }
    private var stamp: Stamp?
    private var cached: [String: String] = [:]
    private static let maximumBytes = 16 * 1024 * 1024

    public init() {}

    public func titles(for hookIDs: Set<String>, in url: URL = CodexSessionTitles.indexURL) -> [String: String] {
        guard !hookIDs.isEmpty else { return [:] }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= Self.maximumBytes,
              let modified = attributes[.modificationDate] as? Date else {
            stamp = nil; cached = [:]
            return [:]
        }
        let next = Stamp(url: url, size: size, modified: modified,
                         inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         requested: hookIDs)
        if next == stamp { return cached }
        guard let handle = try? FileHandle(forReadingFrom: url) else { stamp = nil; cached = [:]; return [:] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumBytes + 1), data.count <= Self.maximumBytes else {
            stamp = nil; cached = [:]
            return [:]
        }
        struct Entry: Decodable { let id: String; let thread_name: String }
        var titles: [String: String] = [:]
        for line in data.split(separator: 10) where line.count <= 65_536 {
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line)),
                  !entry.id.isEmpty, entry.id.count <= 256 else { continue }
            let key = SHA256.hash(data: Data(("codex:" + entry.id).utf8)).map { String(format: "%02x", $0) }.joined()
            guard hookIDs.contains(key) else { continue }
            titles[key] = SessionTitle.normalized(entry.thread_name)
        }
        stamp = next
        cached = titles
        return titles
    }
}
