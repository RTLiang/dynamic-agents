#if NATIVE_LIVE_ACTIVITIES
import AppKit
import CoreServices
import OSLog

@MainActor
final class ActivityHandoffReceiver {
    private var observer: NSObjectProtocol?
    private var inFlight = Set<String>()
    private var completed: [String: String] = [:]
    private var order: [String] = []
    private let logger = Logger(subsystem: AgentHandoff.applicationID, category: "ActivityHandoff")

    init() {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DynamicAgentsHandoff.app")
        if Bundle(url: helper)?.bundleIdentifier == AgentHandoff.helperID {
            let status = LSRegisterURL(helper as CFURL, true)
            if status != noErr { logger.error("Unable to register activity handoff helper: \(status)") }
        }
        observer = DistributedNotificationCenter.default().addObserver(forName: AgentHandoff.requestNotification, object: AgentHandoff.applicationID, queue: .main) { [weak self] notification in
            guard let request = notification.userInfo?["requestID"] as? String,
                  let id = notification.userInfo?["agentID"] as? String else { return }
            Task { @MainActor in self?.receive(id, request: request) }
        }
    }

    private func receive(_ id: String, request: String) {
        guard UUID(uuidString: request) != nil, AgentHandoff.agentID(from: AgentHandoff.url(for: id)) == id else { return }
        if let error = completed[request] { reply(request, error: error); return }
        guard inFlight.count < 32, inFlight.insert(request).inserted else { return }
        Task {
            logger.notice("System activity link received")
            let error: String
            do {
                try await AgentFocusAction.perform(agentID: id)
                error = ""
            } catch let failure { error = failure.localizedDescription }
            inFlight.remove(request)
            completed[request] = error
            order.append(request)
            if order.count > 32 { completed.removeValue(forKey: order.removeFirst()) }
            reply(request, error: error)
        }
    }

    private func reply(_ request: String, error: String) {
        DistributedNotificationCenter.default().postNotificationName(AgentHandoff.replyNotification, object: request, userInfo: ["error": error], deliverImmediately: true)
    }
}
#endif
