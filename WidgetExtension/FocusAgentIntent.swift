import AppIntents
import AppKit
import Foundation
import OSLog

struct FocusAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open App"
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .widgetKitExtension
    static let isDiscoverable = false

    @Parameter(title: "Session") var agentID: String
    @Parameter(title: "Language") var languageIdentifier: String?
    init() { }
    init(agentID: String, languageIdentifier: String? = nil) {
        self.agentID = agentID
        self.languageIdentifier = languageIdentifier
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await WidgetAgentHandoff.focus(agentID, locale: languageIdentifier.map { Locale(identifier: $0) })
        return .result()
    }
}

@MainActor
private enum WidgetAgentHandoff {
    @MainActor private final class PendingReply { var error: String? }

    static func focus(_ agentID: String, locale: Locale?) async throws {
        let request = AgentHandoffRequest(agentID: agentID)
        guard let object = AgentHandoff.requestObject(request) else { throw unavailable(locale) }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard Bundle(url: parent)?.bundleIdentifier == AgentHandoff.applicationID else { throw unavailable(locale) }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: AgentHandoff.applicationID)
        guard running.allSatisfy({ $0.bundleURL?.resolvingSymlinksInPath() == parent.resolvingSymlinksInPath() }) else { throw unavailable(locale) }

        let pending = PendingReply()
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(forName: AgentHandoff.replyNotification, object: nil, queue: .main) { notification in
            guard let object = notification.object as? String, let reply = AgentHandoff.reply(from: object), reply.id == request.id else { return }
            Task { @MainActor in pending.error = reply.error }
        }
        defer { center.removeObserver(observer) }
        if running.isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            configuration.addsToRecentItems = false
            _ = try await NSWorkspace.shared.openApplication(at: parent, configuration: configuration)
        }
        let logger = Logger(subsystem: AgentHandoff.applicationID, category: "ActivityHandoff")
        logger.notice("Widget background action started")
        for attempt in 0..<150 {
            if let error = pending.error {
                guard error.isEmpty else { throw NSError(domain: AgentHandoff.applicationID, code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                logger.notice("Widget background action acknowledged")
                return
            }
            if attempt % 5 == 0 {
                center.postNotificationName(AgentHandoff.requestNotification, object: object, userInfo: nil, deliverImmediately: true)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: AgentHandoff.applicationID, code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.text("Dynamic Agents did not respond. Open the app and try again.", locale: locale)])
    }

    private static func unavailable(_ locale: Locale?) -> NSError { NSError(domain: AgentHandoff.applicationID, code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.text("Unable to open Dynamic Agents.", locale: locale)]) }
}
