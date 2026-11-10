import Foundation

public protocol ActivityAttributes: Codable { associatedtype ContentState: Codable & Hashable }
public struct ActivityContent<S: Codable & Hashable> { public var state: S; public var staleDate: Date?; public init(state: S, staleDate: Date?) { self.state=state;self.staleDate=staleDate } }
public enum ActivityState { case active, stale, ended, dismissed }
public enum ActivityAuthorizationError: Error { case visibility }
public enum ActivityUIDismissalPolicy { case immediate }
public enum FakeActivitySystem {
    public static var instances: [Any]=[]
    public static var requests=0
    public static var updates=0
    public static var authorized=true
    public static var failures=0
    public static var visibilityFailures=0
    public static var pauseNextEnd=false
    public static var endPaused=false
    private static var pendingEnd: CheckedContinuation<Void, Never>?
    public static func reset() { instances=[];requests=0;updates=0;authorized=true;failures=0;visibilityFailures=0;pauseNextEnd=false;endPaused=false }
    public static func waitForEndIfRequested() async {
        if pauseNextEnd {
            pauseNextEnd=false
            endPaused=true
            await withCheckedContinuation { pendingEnd=$0 }
        }
    }
    public static func resumeEnd() { let pending=pendingEnd;pendingEnd=nil;endPaused=false;pending?.resume() }
    public static func loseRegistry() { instances=[] }
}
public final class ActivityAuthorizationInfo { public init() {} ; public var areActivitiesEnabled: Bool { FakeActivitySystem.authorized } }
public final class Activity<A: ActivityAttributes>: Identifiable {
    public let id=UUID().uuidString
    public var activityState=ActivityState.active
    public var content: ActivityContent<A.ContentState>
    private let continuation: AsyncStream<ActivityState>.Continuation
    public let activityStateUpdates: AsyncStream<ActivityState>
    private init(content: ActivityContent<A.ContentState>) {
        self.content=content
        let pair=AsyncStream<ActivityState>.makeStream();activityStateUpdates=pair.stream;continuation=pair.continuation
    }
    public static var activities: [Activity<A>] { FakeActivitySystem.instances.compactMap { $0 as? Activity<A> } }
    public static func request(attributes: A, content: ActivityContent<A.ContentState>, pushType: String? = nil) throws -> Activity<A> {
        FakeActivitySystem.requests+=1
        if FakeActivitySystem.visibilityFailures>0 { FakeActivitySystem.visibilityFailures-=1;throw ActivityAuthorizationError.visibility }
        if FakeActivitySystem.failures>0 { FakeActivitySystem.failures-=1;throw NSError(domain:"ActivityKit",code:7) }
        let activity=Activity(content:content);FakeActivitySystem.instances.append(activity);return activity
    }
    public func update(_ content: ActivityContent<A.ContentState>) async { self.content=content;FakeActivitySystem.updates+=1 }
    public func end(_ content: ActivityContent<A.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy) async {
        if let content { self.content=content }
        transition(.ended)
        await FakeActivitySystem.waitForEndIfRequested()
    }
    public func transition(_ state: ActivityState) {
        activityState=state
        if state == .ended || state == .dismissed { FakeActivitySystem.instances.removeAll { ($0 as? Activity<A>)?.id==id } }
        continuation.yield(state)
    }
}
