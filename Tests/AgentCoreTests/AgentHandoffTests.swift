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

@Test func widgetNotificationPayloadRetainsTheRequestWithoutAUserInfoDictionary() throws {
    let request = AgentHandoffRequest(agentID: "herdr:0123456789ab:wA:p1")
    let object = try #require(AgentHandoff.requestObject(request))
    #expect(AgentHandoff.request(from: object) == request)
    #expect(object.utf8.count <= 4096)
    let reply = try #require(AgentHandoff.replyObject(id: request.id, error: ""))
    #expect(AgentHandoff.reply(from: reply)?.id == request.id)
    #expect(AgentHandoff.reply(from: reply)?.error == "")
}

@Test func widgetNotificationsRejectMalformedAndOversizedUntrustedPayloads() throws {
    let invalid = [
        AgentHandoffRequest(id: "not-a-uuid", agentID: "wA:p1"),
        AgentHandoffRequest(agentID: ""),
        AgentHandoffRequest(agentID: "white space"),
        AgentHandoffRequest(agentID: String(repeating: "x", count: 257))
    ]
    for request in invalid {
        #expect(AgentHandoff.requestObject(request) == nil)
        let object = try JSONEncoder().encode(request).base64EncodedString()
        #expect(AgentHandoff.request(from: object) == nil)
    }
    for object in ["", "not base64!", String(repeating: "A", count: 4097)] {
        #expect(AgentHandoff.request(from: object) == nil)
        #expect(AgentHandoff.reply(from: object) == nil)
    }
    #expect(AgentHandoff.replyObject(id: "not-a-uuid", error: "") == nil)
}

@Test func widgetRepliesBoundTheErrorAndRejectAnUnboundedRemoteReply() throws {
    let id = UUID().uuidString
    let object = try #require(AgentHandoff.replyObject(id: id, error: String(repeating: "界", count: 3000)))
    let reply = try #require(AgentHandoff.reply(from: object))
    #expect(reply.error.count == 512)
    #expect(object.utf8.count <= 4096)
    let oversized = try JSONSerialization.data(withJSONObject: ["id": id, "error": String(repeating: "x", count: 2049)]).base64EncodedString()
    #expect(AgentHandoff.reply(from: oversized) == nil)
}
