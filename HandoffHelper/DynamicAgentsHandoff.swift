import AppKit
import Foundation
import OSLog

@main @MainActor
enum DynamicAgentsHandoffApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = HandoffDelegate()
        app.delegate = delegate
        delegate.start()
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class HandoffDelegate: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?
    private var activityObserver: NSObjectProtocol?
    private let liveActivity = LiveActivityController()
    private var activityConnected = false
    private var activityRequests = Set<String>()
    private var pendingActivity: [AgentActivityServiceRequest] = []
    private var processingActivity = false
    private var activityReplies: [String: Data] = [:]
    private var activityReplyOrder: [String] = []
    private var replies: [String: String] = [:]
    private var currentRequest: String?
    private var pending: [String] = []
    private var pendingDashboard = false
    private var working = false
    private let logger = Logger(subsystem: AgentHandoff.applicationID, category: "ActivityHandoff")

    func start() {
        activityConnected = liveActivity.isRunning
        ProcessInfo.processInfo.disableAutomaticTermination("Hosting agent Live Activities")
        activityObserver = DistributedNotificationCenter.default().addObserver(forName: AgentActivityServiceRequest.notification, object: AgentHandoff.helperID, queue: .main) { [weak self] notification in
            guard let data = notification.userInfo?["payload"] as? Data, data.count <= 16_384,
                  let request = try? JSONDecoder().decode(AgentActivityServiceRequest.self, from: data), UUID(uuidString: request.id) != nil,
                  ["start", "update", "finish", "status"].contains(request.action), request.session.utf8.count <= 256,
                  (request.action != "start" && request.action != "update") || request.state != nil else { return }
            Task { @MainActor in self?.receiveActivity(request) }
        }
        observer = DistributedNotificationCenter.default().addObserver(forName: AgentHandoff.replyNotification, object: nil, queue: .main) { [weak self] notification in
            guard let request = notification.object as? String, let error = notification.userInfo?["error"] as? String else { return }
            Task { @MainActor in
                guard let self, self.currentRequest == request else { return }
                self.replies[request] = error
            }
        }
        checkIdleLater()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingDashboard = pendingDashboard || urls.contains(AgentHandoff.dashboardURL)
        for id in urls.prefix(32).compactMap(AgentHandoff.agentID(from:)) where pending.count < 32 && !pending.contains(id) { pending.append(id) }
        guard !working, pendingDashboard || !pending.isEmpty else { return }
        working = true
        Task {
            while pendingDashboard || !pending.isEmpty {
                do {
                    if pendingDashboard {
                        pendingDashboard = false
                        try await openParent(activates: true)
                    } else { try await send(pending.removeFirst()) }
                } catch {
                    logger.error("Activity handoff failed: \(error.localizedDescription, privacy: .private)")
                    showError(error)
                }
            }
            working = false
            checkIdleLater()
        }
    }

    private func receiveActivity(_ request: AgentActivityServiceRequest) {
        if let data = activityReplies[request.id] { replyActivity(data, id: request.id); return }
        guard activityRequests.count < 32, activityRequests.insert(request.id).inserted else { return }
        pendingActivity.append(request)
        guard !processingActivity else { return }
        processingActivity = true
        Task {
            while !pendingActivity.isEmpty { await processActivity(pendingActivity.removeFirst()) }
            processingActivity = false
            checkIdleLater()
        }
    }

    private func processActivity(_ request: AgentActivityServiceRequest) async {
        let mayStart = request.action == "start" || (request.action == "update" && (!activityConnected || liveActivity.isEnabled))
        let requiresStart = mayStart && !liveActivity.isRunning && request.state?.connected == true && (request.state?.total ?? 0) > 0
        let previousApplication = NSWorkspace.shared.frontmostApplication
        if requiresStart {
            NSApp.setActivationPolicy(.regular)
            NSApp.unhide(nil)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.hides = false
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        switch request.action {
        case "start":
            activityConnected = true
            if let state = request.state { await liveActivity.start(state: state, session: request.session) }
        case "update":
            let wasConnected = activityConnected
            activityConnected = true
            if let state = request.state {
                if wasConnected { await liveActivity.update(state, session: request.session, force: request.forceUpdate == true) }
                else { await liveActivity.start(state: state, session: request.session) }
            }
        case "finish":
            activityConnected = false
            await liveActivity.finish()
        default: break
        }
        if requiresStart {
            let restore = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            NSApp.setActivationPolicy(.prohibited)
            if restore, let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication.activate() }
        }
        activityRequests.remove(request.id)
        if let data = try? JSONEncoder().encode(liveActivity.serviceStatus(id: request.id)) {
            activityReplies[request.id] = data
            activityReplyOrder.append(request.id)
            if activityReplyOrder.count > 32 { activityReplies.removeValue(forKey: activityReplyOrder.removeFirst()) }
            replyActivity(data, id: request.id)
        }
    }

    private func checkIdleLater() {
        guard !activityConnected, !working, !processingActivity else { return }
        Task {
            try? await Task.sleep(for: .seconds(15))
            if !working && !activityConnected && !processingActivity { NSApp.terminate(nil) }
        }
    }

    private func replyActivity(_ data: Data, id: String) {
        DistributedNotificationCenter.default().postNotificationName(AgentActivityServiceReply.notification, object: id, userInfo: ["payload": data], deliverImmediately: true)
    }

    private func openParent(activates: Bool) async throws {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard Bundle(url: parent)?.bundleIdentifier == AgentHandoff.applicationID else { throw unavailable() }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: AgentHandoff.applicationID)
        guard running.allSatisfy({ $0.bundleURL?.resolvingSymlinksInPath() == parent.resolvingSymlinksInPath() }) else { throw unavailable() }
        if running.isEmpty || activates {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = activates
            configuration.hides = !activates
            configuration.addsToRecentItems = false
            _ = try await NSWorkspace.shared.openApplication(at: parent, configuration: configuration)
        }
    }

    private func send(_ id: String) async throws {
        try await openParent(activates: false)
        let request = UUID().uuidString
        currentRequest = request
        defer { replies.removeValue(forKey: request); currentRequest = nil }
        for attempt in 0..<150 {
            if let error = replies[request] {
                if !error.isEmpty { throw NSError(domain: AgentHandoff.applicationID, code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                logger.notice("Activity handoff acknowledged")
                return
            }
            if attempt % 5 == 0 {
                DistributedNotificationCenter.default().postNotificationName(AgentHandoff.requestNotification, object: AgentHandoff.applicationID, userInfo: ["requestID": request, "agentID": id], deliverImmediately: true)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw NSError(domain: AgentHandoff.applicationID, code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.text("Dynamic Agents did not respond. Open the app and try again.")])
    }

    private func showError(_ error: Error) {
        NSApp.setActivationPolicy(.accessory)
        let alert = NSAlert()
        alert.messageText = L10n.text("Action Failed")
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.setActivationPolicy(.prohibited)
    }

    private func unavailable() -> NSError {
        NSError(domain: AgentHandoff.applicationID, code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.text("Unable to open Dynamic Agents.")])
    }
}
