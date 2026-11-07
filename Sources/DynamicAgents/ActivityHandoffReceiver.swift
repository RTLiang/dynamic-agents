#if NATIVE_LIVE_ACTIVITIES
import Foundation
import OSLog

@MainActor
final class ActivityHandoffReceiver {
    private var observer: NSObjectProtocol?
    private var inFlight = Set<String>()
    private var completed: [String: String] = [:]
    private var order: [String] = []
    private let logger = Logger(subsystem: AgentHandoff.applicationID, category: "ActivityHandoff")

    init() {
        observer = DistributedNotificationCenter.default().addObserver(forName: AgentHandoff.requestNotification, object: nil, queue: .main) { [weak self] notification in
            guard let object = notification.object as? String, let request = AgentHandoff.request(from: object) else { return }
            Task { @MainActor in self?.receive(request) }
        }
    }

    private func receive(_ request: AgentHandoffRequest) {
        if let error = completed[request.id] { reply(request.id, error: error); return }
        guard inFlight.count < 32, inFlight.insert(request.id).inserted else { return }
        Task {
            logger.notice("Widget activity action received")
            let error: String
            do {
                try await AgentFocusAction.perform(agentID: request.agentID)
                error = ""
            } catch let failure { error = failure.localizedDescription }
            inFlight.remove(request.id)
            completed[request.id] = error
            order.append(request.id)
            if order.count > 32 { completed.removeValue(forKey: order.removeFirst()) }
            reply(request.id, error: error)
        }
    }

    private func reply(_ request: String, error: String) {
        guard let object = AgentHandoff.replyObject(id: request, error: error) else { return }
        DistributedNotificationCenter.default().postNotificationName(AgentHandoff.replyNotification, object: object, userInfo: nil, deliverImmediately: true)
    }
}
#endif
