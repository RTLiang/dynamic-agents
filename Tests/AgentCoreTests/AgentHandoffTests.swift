import Foundation
import Testing
@testable import AgentCore

@Test func activityLinksPreserveScopedAgentIdentity() {
    for id in ["herdr:0123456789ab:wA:p1", "herdr:abcdef012345:wA:p1", "hook:0123456789abcdef", "pane:with/?&=+%"] {
        let url = AgentHandoff.url(for: id)
        #expect(url.scheme == "dynamicagents-focus")
        #expect(AgentHandoff.agentID(from: url) == id)
    }
    #expect(AgentHandoff.url(for: "herdr:first:wA:p1") != AgentHandoff.url(for: "herdr:second:wA:p1"))
}

@Test func activityLinksRejectAmbiguousOrUnexpectedDestinations() {
    let urls = [
        "https://agent?pane=wA:p1", "dynamicagents-focus://other?pane=wA:p1",
        "dynamicagents-focus://user@agent?pane=wA:p1", "dynamicagents-focus://agent:42?pane=wA:p1",
        "dynamicagents-focus://agent/path?pane=wA:p1", "dynamicagents-focus://agent?pane=wA:p1#fragment",
        "dynamicagents-focus://agent?pane=wA:p1&pane=wB:p1", "dynamicagents-focus://agent?pane=wA:p1&command=other",
        "dynamicagents-focus://agent", "dynamicagents-focus://agent?pane=", "dynamicagents-focus://agent?other=wA:p1",
        "dynamicagents-focus://agent?pane=line%0Abreak", "dynamicagents-focus://agent?pane=white%20space",
        "dynamicagents-focus://agent?pane=%00"
    ]
    for value in urls { #expect(AgentHandoff.agentID(from: URL(string: value)!) == nil) }
}

@Test func activityLinkLimitsUseEncodedByteLength() {
    let limit = String(repeating: "x", count: 256)
    #expect(AgentHandoff.agentID(from: AgentHandoff.url(for: limit)) == limit)
    #expect(AgentHandoff.agentID(from: AgentHandoff.url(for: limit + "x")) == nil)
    #expect(AgentHandoff.agentID(from: AgentHandoff.url(for: String(repeating: "界", count: 86))) == nil)
    #expect(AgentHandoff.agentID(from: AgentHandoff.url(for: String(repeating: "x", count: 5000))) == nil)
}
