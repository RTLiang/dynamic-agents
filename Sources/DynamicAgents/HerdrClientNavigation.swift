import AppKit
@preconcurrency import ApplicationServices
#if SWIFT_PACKAGE
import AgentCore
#endif

@MainActor
enum HerdrClientNavigation {
    private static let keyCodes: [String: CGKeyCode] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
        "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,
        "]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"`":50,
        "enter":36,"return":36,"tab":48,"space":49,"esc":53,"escape":53,"backspace":51,
        "left":123,"right":124,"down":125,"up":126,"home":115,"end":119,"pageup":116,"pagedown":121,
        "f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111
    ]

    static func supports(_ keys: [HerdrNavigationKey]) -> Bool { keys.allSatisfy { keyCodes[$0.key] != nil } }

    static func open(paneID: String, target: TerminalFocusTarget, client: HerdrClient? = nil) async throws {
        try await HerdrDirectNavigation.open(paneID: paneID, target: target, client: client)
    }

    static func currentPane(target: TerminalFocusTarget) async throws -> String? {
        try validate(target)
        if let attached = target.client.attachedPaneID { return attached }
        guard AXIsProcessTrusted() else { throw unreadable() }
        let keys = try HerdrNavigationKeys.load(path: target.client.configPath)
        guard keys.openNavigator.allSatisfy({ keyCodes[$0.key] != nil }) else {
            throw failure("Unable to read the herdr navigation shortcuts. Check its prefix and goto keybindings.")
        }
        if HerdrNavigatorSnapshot(screen: try await availableScreen(target)) != nil { try await closeNavigator(target) }
        do {
            try await openNavigator(keys, target: target)
            let pane = try await navigator(target).selectedPaneID
            try await closeNavigator(target)
            return pane
        } catch {
            try? await closeNavigator(target)
            throw error
        }
    }

    static func validate(_ target: TerminalFocusTarget) throws {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool == true {
            throw failure("Unlock your Mac before selecting an existing herdr page.")
        }
        guard let started = target.client.startedAt,
              ProcessInventory.startedAt(pid: target.client.processID) == started,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.client.application.pid,
              try TerminalAutomation.focusedSurfaceID(in: target.client.application) == target.surface.id else {
            throw failure("The selected terminal view changed. Try the action again.")
        }
    }

    private static func screen(_ target: TerminalFocusTarget) throws -> String {
        try validate(target)
        let element = try textArea(target)
        guard let rangeValue = attribute(element, kAXVisibleCharacterRangeAttribute) else { throw unreadable() }
        var text: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &text) == .success,
           let string = text as? String, string.utf8.count <= 131_072 { return string }
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else { throw unreadable() }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0,
              let full = attribute(element, kAXValueAttribute) as? String else { throw unreadable() }
        let string = full as NSString
        guard range.location <= string.length, range.length <= string.length - range.location, range.length <= 131_072 else { throw unreadable() }
        return string.substring(with: NSRange(location: range.location, length: range.length))
    }

    static func textArea(_ target: TerminalFocusTarget) throws -> AXUIElement {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            let element = value as! AXUIElement
            var pid: Int32 = 0
            AXUIElementGetPid(element, &pid)
            if pid == target.client.application.pid, attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole { return element }
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let window = windows.first { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 == target.client.application.pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let data = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: data) else { return false }
            return rect.width > 100 && rect.height > 100
        }
        guard let window, let data = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: data) else { throw unreadable() }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(rect.midX), Float(rect.midY), &hit) == .success, var root = hit else { throw unreadable() }
        var owner: Int32 = 0
        AXUIElementGetPid(root, &owner)
        guard owner == target.client.application.pid else { throw unreadable() }
        for _ in 0..<16 {
            if attribute(root, kAXRoleAttribute) as? String == kAXWindowRole { break }
            guard let parent = attribute(root, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { throw unreadable() }
            root = parent as! AXUIElement
        }
        guard attribute(root, kAXRoleAttribute) as? String == kAXWindowRole else { throw unreadable() }
        var areas: [AXUIElement] = []
        var visited = 0
        func collect(_ element: AXUIElement, depth: Int) {
            guard depth < 18, visited < 1500 else { return }
            visited += 1
            if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole { areas.append(element); return }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(100) { collect(child, depth: depth + 1) }
        }
        collect(root, depth: 0)
        let focused = areas.filter { (attribute($0, kAXFocusedAttribute) as? NSNumber)?.boolValue == true }
        if focused.count == 1 { return focused[0] }
        guard areas.count == 1 else { throw unreadable() }
        return areas[0]
    }

    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value
    }

    static func tap(_ key: HerdrNavigationKey, target: TerminalFocusTarget) throws {
        try validate(target)
        if try TerminalAutomation.sendKey(key, to: target.surface, application: target.client.application) { return }
        guard let code = keyCodes[key.key] else { throw unreadable() }
        var flags: CGEventFlags = []
        if key.modifiers.contains("control") { flags.insert(.maskControl) }
        if key.modifiers.contains("option") { flags.insert(.maskAlternate) }
        if key.modifiers.contains("command") { flags.insert(.maskCommand) }
        if key.modifiers.contains("shift") { flags.insert(.maskShift) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { throw unreadable() }
            event.flags = flags
            if key.key.count == 1, !key.modifiers.contains("control"), !key.modifiers.contains("command") {
                let units = Array((key.modifiers.contains("shift") ? key.key.uppercased() : key.key).utf16)
                units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!) }
            }
            event.postToPid(target.client.application.pid)
        }
    }

    private static func type(_ character: Character, target: TerminalFocusTarget) throws {
        let units = Array(String(character).utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { throw unreadable() }
            event.flags = []
            units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!) }
            event.postToPid(target.client.application.pid)
        }
    }

    private static func openNavigator(_ keys: HerdrNavigationKeys, target: TerminalFocusTarget) async throws {
        for (index, key) in keys.openNavigator.enumerated() {
            if index == 0, keys.openNavigator.count == 2, prefixMode(try await availableScreen(target)) { continue }
            try tap(key, target: target)
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try await navigator(target)
    }

    private static func navigator(_ target: TerminalFocusTarget, matching predicate: (HerdrNavigatorSnapshot) -> Bool = { _ in true }) async throws -> HerdrNavigatorSnapshot {
        var result: HerdrNavigatorSnapshot?
        try await waitUntil(target) {
            guard let snapshot = HerdrNavigatorSnapshot(screen: $0), predicate(snapshot) else { return false }
            result = snapshot
            return true
        }
        guard let result else { throw unreadable() }
        return result
    }

    static func availableScreen(_ target: TerminalFocusTarget) async throws -> String {
        var text = ""
        try await waitUntil(target) { text = $0; return true }
        return text
    }

    private static func waitUntil(_ target: TerminalFocusTarget, _ predicate: (String) -> Bool) async throws {
        for _ in 0..<30 {
            try validate(target)
            if let text = try? screen(target), predicate(text) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw unreadable()
    }

    private static func closeNavigator(_ target: TerminalFocusTarget) async throws {
        for _ in 0..<2 {
            let visible = try await availableScreen(target)
            guard HerdrNavigatorSnapshot(screen: visible) != nil || prefixMode(visible) else { return }
            try tap(try HerdrNavigationKey("escape"), target: target)
            try await Task.sleep(for: .milliseconds(60))
        }
    }

    private static func prefixMode(_ text: String) -> Bool {
        guard let footer = text.components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
        return footer.contains("PREFIX") && footer.contains("send prefix")
    }

    private static func unreadable() -> HerdrError { failure("Unable to verify the existing herdr page. Keep its terminal window visible and try again.") }
    private static func failure(_ key: String) -> HerdrError { .message(L10n.text(key)) }
}
