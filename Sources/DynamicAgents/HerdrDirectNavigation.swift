import AppKit
@preconcurrency import ApplicationServices
import Darwin
#if SWIFT_PACKAGE
import AgentCore
#endif

@MainActor
enum HerdrDirectNavigation {
    static func open(paneID: String, target: TerminalFocusTarget, client: HerdrClient?) async throws {
        try HerdrClientNavigation.validate(target)
        guard target.client.attachedPaneID == nil,
              paneID.range(of: "^[A-Za-z0-9_-]+:p[0-9]+$", options: .regularExpression) != nil else { throw unavailable() }
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary), CGPreflightPostEventAccess() else {
            throw HerdrError.message(L10n.text("Allow Dynamic Agents in System Settings > Privacy & Security > Accessibility to select existing herdr pages."))
        }
        let server = client ?? HerdrClient(session: target.client.session)
        let socket = try await server.socketPath()
        var snapshot = try await server.navigationSnapshot(socketPath: socket)
        guard snapshot.agents.contains(where: { $0.paneID == paneID }) else { throw unavailable() }
        let initial = try await HerdrClientNavigation.availableScreen(target)
        let prefixActive = initial.components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?.contains("PREFIX") ?? false
        guard HerdrNavigatorSnapshot(screen: initial) == nil, HerdrNavigationSnapshot.agentHeader(in: initial) != nil,
              !prefixActive else { throw sidebarUnavailable() }
        let previousPointer = CGEvent(source: nil)?.location
        var lastPointer: CGPoint?
        defer {
            if let previousPointer, let lastPointer, let current = CGEvent(source: nil)?.location,
               abs(current.x - lastPointer.x) < 2, abs(current.y - lastPointer.y) < 2 {
                CGWarpMouseCursorPosition(previousPointer)
            }
        }

        // A client-local pane cycle establishes its own focus context before reading the
        // server's default focus. No public focus API or navigator is involved.
        let keys = try HerdrNavigationKeys.load(path: target.client.configPath, useNavigator: false)
        let cycle = try keys.cyclePane()
        guard HerdrClientNavigation.supports(cycle) else { throw unavailable() }
        for key in cycle { try HerdrClientNavigation.tap(key, target: target) }
        try await Task.sleep(for: .milliseconds(35))
        snapshot = try await server.navigationSnapshot(socketPath: socket)
        var screen = try await HerdrClientNavigation.availableScreen(target)
        var row = snapshot.visibleAgentRow(for: paneID, screen: screen)
        if row == nil, let header = HerdrNavigationSnapshot.agentHeader(in: screen) {
            lastPointer = try await scroll(target, screen: screen, row: header + 4, lines: 1000)
            try await Task.sleep(for: .milliseconds(30))
            for _ in 0..<12 {
                screen = try await HerdrClientNavigation.availableScreen(target)
                snapshot = try await server.navigationSnapshot(socketPath: socket)
                row = snapshot.visibleAgentRow(for: paneID, screen: screen)
                if row != nil { break }
                lastPointer = try await scroll(target, screen: screen, row: header + 4, lines: -8)
                try await Task.sleep(for: .milliseconds(30))
            }
        }
        guard let row else { throw sidebarUnavailable() }
        lastPointer = try await click(target, screen: screen, row: row)
        for _ in 0..<20 {
            try HerdrClientNavigation.validate(target)
            let result = try await server.navigationSnapshot(socketPath: socket)
            if result.focusedPaneID == paneID { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw unavailable()
    }

    private static func click(_ target: TerminalFocusTarget, screen: String, row: Int) async throws -> CGPoint {
        let point = try point(target, screen: screen, row: row)
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { throw unavailable() }
        move.flags = []
        move.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
            if event.type == .leftMouseDown { try? await Task.sleep(for: .milliseconds(20)) }
        }
        return point
    }

    private static func scroll(_ target: TerminalFocusTarget, screen: String, row: Int, lines: Int32) async throws -> CGPoint {
        let point = try point(target, screen: screen, row: row)
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else { throw unavailable() }
        move.flags = []
        move.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(20))
        event.location = point
        event.flags = []
        event.post(tap: .cghidEventTap)
        return point
    }

    private static func point(_ target: TerminalFocusTarget, screen: String, row: Int) throws -> CGPoint {
        try HerdrClientNavigation.validate(target)
        let area = try HerdrClientNavigation.textArea(target)
        guard let rawPosition = attribute(area, kAXPositionAttribute), let rawSize = attribute(area, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { throw unavailable() }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin), AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
              size.width > 100, size.height > 100, target.surface.tty.hasPrefix("/dev/") else { throw unavailable() }
        let fd = Darwin.open(target.surface.tty, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw unavailable() }
        defer { Darwin.close(fd) }
        var geometry = winsize()
        guard isatty(fd) == 1, ioctl(fd, TIOCGWINSZ, &geometry) == 0,
              geometry.ws_row > 0, geometry.ws_col >= 20, row >= 0, row < Int(geometry.ws_row) else { throw unavailable() }
        let lines = screen.components(separatedBy: .newlines)
        guard lines.count == Int(geometry.ws_row) || lines.count == Int(geometry.ws_row) + 1 else { throw unavailable() }
        var point: CGPoint?
        if let visible = attribute(area, kAXVisibleCharacterRangeAttribute), CFGetTypeID(visible) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(visible as! AXValue, .cfRange, &range) {
                let offset = lines.prefix(row).reduce(0) { $0 + $1.utf16.count + 1 }
                var cellRange = CFRange(location: range.location + offset + min(3, lines[row].utf16.count), length: 1)
                if let encoded = AXValueCreate(.cfRange, &cellRange) {
                    var value: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(area, kAXBoundsForRangeParameterizedAttribute as CFString, encoded, &value) == .success,
                       let value, CFGetTypeID(value) == AXValueGetTypeID() {
                        var bounds = CGRect.zero
                        if AXValueGetValue(value as! AXValue, .cgRect, &bounds), bounds.height > 0 { point = CGPoint(x: bounds.midX, y: bounds.midY) }
                    }
                }
            }
        }
        if point == nil {
            point = CGPoint(x: origin.x + size.width * 5 / CGFloat(geometry.ws_col),
                            y: origin.y + size.height * (CGFloat(row) + 0.5) / CGFloat(geometry.ws_row))
        }
        guard let point, CGRect(origin: origin, size: size).contains(point) else { throw unavailable() }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success, let hit else { throw unavailable() }
        var owner: Int32 = 0
        AXUIElementGetPid(hit, &owner)
        guard owner == target.client.application.pid else { throw unavailable() }
        return point
    }

    private static func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(node, key as CFString, &value)
        return value
    }
    private static func unavailable() -> HerdrError {
        .message(L10n.text("Unable to verify the existing herdr page. Keep its terminal window visible and try again."))
    }
    private static func sidebarUnavailable() -> HerdrError {
        .message(L10n.text("Show herdr's sidebar with a unique workspace, tab and agent label, close any dialog, then try again."))
    }
}
