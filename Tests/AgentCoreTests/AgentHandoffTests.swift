import Foundation
import Testing
@testable import AgentCore

private let hookID = "hook:" + String(repeating: "a", count: 40)

@Test func activityLinksPreserveHookIdentity() {
    let url = AgentHandoff.url(for: hookID)
    #expect(url.scheme == "dynamicagents-focus")
    #expect(AgentHandoff.agentID(from: url) == hookID)
    #expect(AgentHandoff.agentID(from: AgentHandoff.url(for: "hook:" + String(repeating: "b", count: 40))) != hookID)
}

@Test func activityLinksRejectUnexpectedDestinationsAndNonHookIDs() {
    let urls = [
        "https://agent?session=\(hookID)", "dynamicagents-focus://other?session=\(hookID)",
        "dynamicagents-focus://user@agent?session=\(hookID)", "dynamicagents-focus://agent:42?session=\(hookID)",
        "dynamicagents-focus://agent/path?session=\(hookID)", "dynamicagents-focus://agent?session=\(hookID)#fragment",
        "dynamicagents-focus://agent?session=\(hookID)&session=\(hookID)", "dynamicagents-focus://agent?session=\(hookID)&command=other",
        "dynamicagents-focus://agent", "dynamicagents-focus://agent?session=", "dynamicagents-focus://agent?other=\(hookID)"
    ]
    for value in urls { #expect(AgentHandoff.agentID(from: URL(string: value)!) == nil) }
    for id in ["w1:p1", "not-a-hook", "hook:" + String(repeating: "a", count: 41), "hook:" + String(repeating: "界", count: 40), String(repeating: "x", count: 5000)] {
        #expect(AgentHandoff.agentID(from: AgentHandoff.url(for: id)) == nil)
    }
}

@Test func widgetNotificationPayloadUsesOnlyTheObjectString() throws {
    let request = AgentHandoffRequest(agentID: hookID)
    let object = try #require(AgentHandoff.requestObject(request))
    #expect(AgentHandoff.request(from: object) == request)
    #expect(object.utf8.count <= 4096)
    let reply = try #require(AgentHandoff.replyObject(id: request.id, error: ""))
    #expect(AgentHandoff.reply(from: reply)?.id == request.id)
    #expect(AgentHandoff.reply(from: reply)?.error == "")
}

@Test func widgetNotificationsRejectMalformedAndOversizedPayloads() throws {
    let invalid = [AgentHandoffRequest(id: "not-a-uuid", agentID: hookID), AgentHandoffRequest(agentID: ""), AgentHandoffRequest(agentID: "white space"), AgentHandoffRequest(agentID: String(repeating: "x", count: 257))]
    for request in invalid {
        #expect(AgentHandoff.requestObject(request) == nil)
        #expect(AgentHandoff.request(from: try JSONEncoder().encode(request).base64EncodedString()) == nil)
    }
    for object in ["", "not base64!", String(repeating: "A", count: 4097)] {
        #expect(AgentHandoff.request(from: object) == nil)
        #expect(AgentHandoff.reply(from: object) == nil)
    }
    #expect(AgentHandoff.replyObject(id: "not-a-uuid", error: "") == nil)
}

@Test func widgetRepliesBoundErrors() throws {
    let id = UUID().uuidString
    let object = try #require(AgentHandoff.replyObject(id: id, error: String(repeating: "界", count: 3000)))
    let reply = try #require(AgentHandoff.reply(from: object))
    #expect(reply.error.count == 512 && object.utf8.count <= 4096)
    let oversized = try JSONSerialization.data(withJSONObject: ["id": id, "error": String(repeating: "x", count: 2049)]).base64EncodedString()
    #expect(AgentHandoff.reply(from: oversized) == nil)
}
