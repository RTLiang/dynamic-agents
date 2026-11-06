#if NATIVE_LIVE_ACTIVITIES
import ActivityKit
import Foundation

@available(macOS 27.3, *)
struct AgentActivityAttributes: ActivityAttributes, Sendable {
    typealias ContentState = AgentActivityState
    let sessionName: String
}
#endif
