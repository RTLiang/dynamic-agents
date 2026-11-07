#if !ACTIVITY_SERVICE
import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AgentCore
#endif

@Observable @MainActor
final class LiveActivityController {
    private(set) var isEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
    private(set) var isRunning = false
    private(set) var isStarting = false
    private(set) var message: String?
    private(set) var status: AgentActivityServiceReply?
    private var observer: NSObjectProtocol?
    private var replies: [String: AgentActivityServiceReply] = [:]
    private var pendingRequest: String?
    private var generation = 0
    var isSupported: Bool {
        #if NATIVE_LIVE_ACTIVITIES
        if #available(macOS 27.3, *) { return true }
        #endif
        return false
    }

    init() {
        observer = DistributedNotificationCenter.default().addObserver(forName: AgentActivityServiceReply.notification, object: nil, queue: .main) { [weak self] notification in
            guard let data = notification.userInfo?["payload"] as? Data, data.count <= 16_384,
                  let reply = try? JSONDecoder().decode(AgentActivityServiceReply.self, from: data) else { return }
            Task { @MainActor in
                guard let self, self.pendingRequest == reply.id else { return }
                self.replies[reply.id] = reply
            }
        }
        if !isSupported { message = L10n.text("Live Activities require the native app with its widget extension.") }
    }

    func start(state: AgentActivityState, session: String) async {
        guard isSupported else { return }
        generation += 1
        isEnabled = true
        UserDefaults.standard.set(true, forKey: "liveActivityEnabled")
        guard await waitUntilIdle() else { return }
        await send(action: "start", state: state, session: session)
    }

    func update(_ state: AgentActivityState, session: String, force: Bool = false) async {
        guard isSupported, isEnabled, !isStarting else { return }
        await send(action: "update", state: state, session: session, force: force)
    }

    func refreshStatus() async {
        guard isSupported, !isStarting else { return }
        await send(action: "status", state: nil, session: "")
    }

    func stop() async {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: "liveActivityEnabled")
        await finish()
    }

    func finish() async {
        generation += 1
        isEnabled = false
        guard isSupported else { isRunning = false; return }
        guard await waitUntilIdle() else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: AgentHandoff.helperID).isEmpty else { isRunning = false; return }
        await send(action: "finish", state: nil, session: "")
        isRunning = false
    }

    func finishForTermination() {
        generation += 1
        isEnabled = false
        isRunning = false
        guard isSupported, let data = try? JSONEncoder().encode(AgentActivityServiceRequest(action: "finish")) else { return }
        DistributedNotificationCenter.default().postNotificationName(AgentActivityServiceRequest.notification, object: AgentHandoff.helperID, userInfo: ["payload": data], deliverImmediately: true)
    }

    private func waitUntilIdle() async -> Bool {
        for _ in 0..<130 {
            if !isStarting { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !isStarting
    }

    private func send(action: String, state: AgentActivityState?, session: String, force: Bool = false) async {
        guard !isStarting else { return }
        let requestGeneration = generation
        isStarting = true
        defer { isStarting = false }
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/DynamicAgentsHandoff.app")
            guard Bundle(url: helper)?.bundleIdentifier == AgentHandoff.helperID else { throw unavailable() }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: AgentHandoff.helperID)
            guard running.allSatisfy({ $0.bundleURL?.resolvingSymlinksInPath() == helper.resolvingSymlinksInPath() }) else { throw unavailable() }
            if running.isEmpty {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.hides = false
                config.addsToRecentItems = false
                _ = try await NSWorkspace.shared.openApplication(at: helper, configuration: config)
            }
            let request = AgentActivityServiceRequest(action: action, state: state, session: session, forceUpdate: force)
            let data = try JSONEncoder().encode(request)
            guard data.count <= 16_384 else { throw unavailable() }
            pendingRequest = request.id
            defer { replies.removeValue(forKey: request.id); pendingRequest = nil }
            for attempt in 0..<100 {
                if let reply = replies[request.id] {
                    guard requestGeneration == generation else { return }
                    status = reply
                    isRunning = reply.running
                    message = reply.message
                    if action != "finish" {
                        isEnabled = reply.enabled
                        UserDefaults.standard.set(reply.enabled, forKey: "liveActivityEnabled")
                    }
                    return
                }
                if attempt % 10 == 0 {
                    DistributedNotificationCenter.default().postNotificationName(AgentActivityServiceRequest.notification, object: AgentHandoff.helperID, userInfo: ["payload": data], deliverImmediately: true)
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw unavailable()
        } catch {
            if requestGeneration == generation { message = error.localizedDescription; isRunning = false }
        }
    }

    private func unavailable() -> HerdrError { .message(L10n.text("Dynamic Agents did not respond. Open the app and try again.")) }
}
#endif
