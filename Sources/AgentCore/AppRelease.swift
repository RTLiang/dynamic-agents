import Foundation

public struct ReleaseVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    private let parts: [Int]
    public let description: String

    public init?(_ value: String) {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = version.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ field in
            !field.isEmpty && field.count <= 9 && field.utf8.allSatisfy { (48...57).contains($0) }
                && (field.count == 1 || field.first != "0")
        }) else { return nil }
        parts = fields.compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        description = version
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public struct AppRelease: Equatable, Sendable {
    public static let repository = "RTLiang/dynamic-agents"
    public let version: ReleaseVersion
    public let pageURL: URL
    public let downloadURL: URL

    public static func decode(_ data: Data) throws -> Self? {
        struct Response: Decodable {
            let tag_name: String
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
        }
        let release = try JSONDecoder().decode(Response.self, from: data)
        guard !release.draft, !release.prerelease, let version = ReleaseVersion(release.tag_name) else { return nil }
        let root = "https://github.com/" + repository + "/releases/"
        guard release.html_url.absoluteString == root + "tag/" + release.tag_name else { return nil }
        let filename = "DynamicAgents-\(version)-arm64.dmg"
        guard let asset = release.assets.first(where: { $0.name == filename }),
              asset.browser_download_url.absoluteString == root + "download/" + release.tag_name + "/" + filename else { return nil }
        return Self(version: version, pageURL: release.html_url, downloadURL: asset.browser_download_url)
    }

    public static func latest() async throws -> Self? {
        let url = URL(string: "https://api.github.com/repos/" + repository + "/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpShouldHandleCookies = false
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DynamicAgents", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AgentError.message(L10n.text("Invalid update response.")) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200, data.count <= 2_097_152 else {
            throw AgentError.message(L10n.format("Update service returned HTTP %lld.", Int64(http.statusCode)))
        }
        return try decode(data)
    }
}
