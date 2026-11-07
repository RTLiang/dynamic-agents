import Foundation
import Testing
@testable import AgentCore

@Test func releaseVersionsCompareNumericallyAndRejectNonStableTags() throws {
    let newer = try #require(ReleaseVersion("v1.10.0"))
    let older = try #require(ReleaseVersion("1.9.9"))
    #expect(newer > older)
    #expect(ReleaseVersion("v0.1.0") == ReleaseVersion("0.1.0"))
    for value in ["1.2", "1.2.3.4", "1.2.3-beta", "1.2.3+build", "01.2.3", "-1.2.3", "1.2.3\n", "1.2.999999999999999999999999"] {
        #expect(ReleaseVersion(value) == nil)
    }
}

private func releaseFixture(tag: String = "v1.10.0", draft: Bool = false, prerelease: Bool = false,
                            page: String? = nil, download: String? = nil, filename: String = "DynamicAgents-1.10.0-arm64.zip") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "tag_name": tag, "draft": draft, "prerelease": prerelease,
        "html_url": page ?? "https://github.com/RTLiang/dynamic-agents/releases/tag/" + tag,
        "assets": [["name": filename, "browser_download_url": download ?? "https://github.com/RTLiang/dynamic-agents/releases/download/\(tag)/\(filename)"]]
    ])
}

@Test func releaseRequiresStableTagAndTheNativeArchive() throws {
    let decoded = try AppRelease.decode(releaseFixture())
    let release = try #require(decoded)
    #expect(release.version == ReleaseVersion("1.10.0"))
    #expect(release.downloadURL.lastPathComponent == "DynamicAgents-1.10.0-arm64.zip")
    #expect(try AppRelease.decode(releaseFixture(draft: true)) == nil)
    #expect(try AppRelease.decode(releaseFixture(prerelease: true)) == nil)
    #expect(try AppRelease.decode(releaseFixture(tag: "v1.10.0-beta")) == nil)
    #expect(try AppRelease.decode(releaseFixture(filename: "DynamicAgents-Companion.zip")) == nil)
}

@Test func updateLinksStayWithinTheExpectedRepositoryAndTag() throws {
    for page in ["https://example.invalid/release", "http://github.com/RTLiang/dynamic-agents/releases/tag/v1.10.0", "https://github.com/another/repo/releases/tag/v1.10.0"] {
        #expect(try AppRelease.decode(releaseFixture(page: page)) == nil)
    }
    for url in ["https://example.invalid/app.zip", "https://github.com/another/repo/releases/download/v1.10.0/DynamicAgents-1.10.0-arm64.zip", "https://github.com/RTLiang/dynamic-agents/releases/download/v1.9.0/DynamicAgents-1.10.0-arm64.zip"] {
        #expect(try AppRelease.decode(releaseFixture(download: url)) == nil)
    }
}
