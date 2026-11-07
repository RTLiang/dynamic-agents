import Foundation

public struct HerdrNavigationKey: Equatable, Sendable {
    public let key: String
    public let modifiers: Set<String>

    public init(_ binding: String) throws {
        var parts = binding.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.popLast(), !last.isEmpty else { throw HerdrNavigationKeys.unsupported() }
        var flags = Set<String>()
        for part in parts {
            switch part.lowercased() {
            case "ctrl", "control": flags.insert("control")
            case "alt", "option": flags.insert("option")
            case "cmd", "command", "super", "meta": flags.insert("command")
            case "shift": flags.insert("shift")
            default: throw HerdrNavigationKeys.unsupported()
            }
        }
        if last.count == 1, last != last.lowercased() { flags.insert("shift") }
        key = last.lowercased()
        modifiers = flags
    }
}

public struct HerdrNavigationKeys: Equatable, Sendable {
    public let openNavigator: [HerdrNavigationKey]

    public static func load(path: String?) throws -> Self {
        let url = path.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr/config.toml")
        guard FileManager.default.fileExists(atPath: url.path) else {
            if path != nil { throw unsupported() }
            return try parse("")
        }
        let resolved = url.resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576,
              let text = String(data: try Data(contentsOf: resolved), encoding: .utf8) else { throw unsupported() }
        return try parse(text)
    }

    public static func parse(_ content: String) throws -> Self {
        var section = ""
        var multiline: String?
        var overrides: [String: String] = [:]
        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let delimiter = multiline {
                if line.contains(delimiter) { multiline = nil }
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                guard let end = line.firstIndex(of: "]") else { throw unsupported() }
                section = String(line[line.index(after: line.startIndex)..<end]).trimmingCharacters(in: .whitespaces)
                if section == "keys.prefix" || section == "keys.goto" { throw unsupported() }
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let field = section == "keys" ? name : section.isEmpty && name.hasPrefix("keys.") ? String(name.dropFirst(5)) : ""
            if ["prefix", "goto"].contains(field) {
                guard overrides[field] == nil else { throw unsupported() }
                overrides[field] = try firstBinding(value)
            } else {
                if name == "keys", section.isEmpty { throw unsupported() }
                for delimiter in ["\"\"\"", "'''"] where value.hasPrefix(delimiter) {
                    if !value.dropFirst(3).contains(delimiter) { multiline = delimiter }
                }
            }
        }
        let prefix = overrides["prefix"] ?? "ctrl+b"
        let destination = overrides["goto"] ?? "prefix+g"
        if destination.lowercased().hasPrefix("prefix+") {
            return Self(openNavigator: [try HerdrNavigationKey(prefix), try HerdrNavigationKey(String(destination.dropFirst(7)))])
        }
        return Self(openNavigator: [try HerdrNavigationKey(destination)])
    }

    private static func firstBinding(_ source: String) throws -> String {
        var quote: Character?
        var escaped = false
        var clean = ""
        for char in source {
            if char == "#", quote == nil { break }
            clean.append(char)
            if escaped { escaped = false; continue }
            if quote == "\"", char == "\\" { escaped = true; continue }
            if char == quote { quote = nil }
            else if quote == nil, char == "\"" || char == "'" { quote = char }
        }
        clean = clean.trimmingCharacters(in: .whitespaces)
        guard quote == nil, !clean.hasPrefix("\"\"\""), !clean.hasPrefix("'''") else { throw unsupported() }
        if clean.hasPrefix("[") {
            guard let values = try? JSONDecoder().decode([String].self, from: Data(clean.utf8)), let first = values.first, !first.isEmpty else { throw unsupported() }
            return first
        }
        if clean.hasPrefix("'"), clean.hasSuffix("'"), clean.count >= 2 { return String(clean.dropFirst().dropLast()) }
        guard let value = try? JSONDecoder().decode(String.self, from: Data(clean.utf8)), !value.isEmpty else { throw unsupported() }
        return value
    }

    static func unsupported() -> HerdrError {
        .message(L10n.text("Unable to read the herdr navigation shortcuts. Check its prefix and goto keybindings."))
    }
}
