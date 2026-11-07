import Foundation

public struct HerdrNavigatorSnapshot: Equatable, Sendable {
    public let terminalCount: Int
    public let searchFocused: Bool
    public let selectedPaneID: String?

    public init?(screen: String) {
        let lines = screen.components(separatedBy: .newlines)
        guard let footer = lines.lastIndex(where: { $0.contains("search type · move") || $0.contains("rows · ←→ workspace") }),
              footer >= 3,
              let heading = lines[..<footer].lastIndex(where: { $0.contains(" Go to ") }),
              footer - heading <= 44,
              heading + 1 < lines.count else { return nil }
        let header = lines[heading + 1]
        guard let countRange = header.range(of: "[0-9]+ terminals?", options: .regularExpression),
              let count = Int(header[countRange].split(separator: " ")[0]) else { return nil }
        terminalCount = count
        searchFocused = lines[footer].contains("search type · move")
        let detail = lines[footer - 2]
        if let range = detail.range(of: "[A-Za-z0-9_-]+:p[0-9]+(?=[ \\t│┃|]*$)", options: .regularExpression) {
            selectedPaneID = String(detail[range])
        } else { selectedPaneID = nil }
    }
}
