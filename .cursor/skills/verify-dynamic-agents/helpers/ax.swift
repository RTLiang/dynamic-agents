import AppKit
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func find(_ element: AXUIElement, depth: Int = 0, matching: (AXUIElement) -> Bool) -> AXUIElement? {
    guard depth < 22 else { return nil }
    if matching(element) { return element }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let match = find(child, depth: depth + 1, matching: matching) { return match }
    }
    return nil
}
func labels(_ element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attribute(element, $0) as? String }
}
func waitFor(_ seconds: TimeInterval = 0.4) { RunLoop.current.run(until: .now.addingTimeInterval(seconds)) }
func require(_ condition: Bool, _ message: String) {
    guard condition else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
}
func tree(_ element: AXUIElement, depth: Int = 0) -> [String: Any] {
    let role = attribute(element, kAXRoleAttribute) as? String ?? ""
    let identifiers = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXValueAttribute, kAXHelpAttribute]
    var result: [String: Any] = ["role": role]
    for key in identifiers {
        if let value = attribute(element, key) as? String, !value.isEmpty { result[key] = value }
        else if let value = attribute(element, key) as? NSNumber { result[key] = value }
    }
    if depth < 16, role != kAXMenuBarRole {
        let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        if !children.isEmpty { result["children"] = children.map { tree($0, depth: depth + 1) } }
    }
    return result
}
let arguments = CommandLine.arguments
require(arguments.count >= 4, "usage: ax <pid> <bundle-id> <doctor|snapshot|duration>")
require(AXIsProcessTrusted(), "Accessibility permission is required for the tool launching this helper")
if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
   (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true {
    require(false, "macOS session is locked; unlock before driving UI")
}
guard let pid = Int32(arguments[1]) else { require(false, "invalid PID"); exit(1) }
var candidate: NSRunningApplication?
for _ in 0..<50 {
    candidate = NSRunningApplication(processIdentifier: pid)
    if candidate?.bundleIdentifier == arguments[2] { break }
    waitFor(0.1)
}
guard let app = candidate, app.bundleIdentifier == arguments[2], !app.isTerminated else { require(false, "wrong or missing app process"); exit(1) }
let root = AXUIElementCreateApplication(pid)
let action = arguments[3]
if action == "doctor" {
    var ready = false
    for _ in 0..<50 {
        let table = find(root) { attribute($0, kAXIdentifierAttribute) as? String == "agents-table" }
        let first = find(root) { attribute($0, kAXValueAttribute) as? String == "Build example" }
        let second = find(root) { attribute($0, kAXValueAttribute) as? String == "Review example" }
        let connected = find(root) { attribute($0, kAXValueAttribute) as? String == "herdr connected" }
        ready = table != nil && first != nil && second != nil && connected != nil
        if ready { break }
        waitFor(0.2)
    }
    if !ready, let data = try? JSONSerialization.data(withJSONObject: tree(root), options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
    require(ready, "dashboard and both fixture agents are not ready")
    print("ready: isolated app PID \(pid), connected dashboard with both fixture agents")
} else if action == "snapshot" {
    let data = try JSONSerialization.data(withJSONObject: tree(root), options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} else if action == "menu" {
    guard let raw = attribute(root, "AXExtrasMenuBar"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { print("menu icon: absent"); exit(0) }
    let menu = raw as! AXUIElement
    let items = attribute(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let present = items.contains { labels($0).contains("Dynamic Agents") }
    print("menu icon: \(present ? "present" : "absent")")
} else if action == "press" {
    require(arguments.count == 6, "usage: ax <pid> <bundle-id> press <AX-role> <label>")
    guard let element = find(root, matching: { attribute($0, kAXRoleAttribute) as? String == arguments[4] && labels($0).contains(arguments[5]) }) else {
        require(false, "element not found: \(arguments[4]) \(arguments[5])"); exit(1)
    }
    require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "AXPress failed")
    waitFor()
    print("pressed \(arguments[4]) \(arguments[5])")
} else if action == "set" {
    require(arguments.count == 6, "usage: ax <pid> <bundle-id> set <AXIdentifier> <value>")
    guard let element = find(root, matching: {
        if arguments[4].hasPrefix("role:") { return attribute($0, kAXRoleAttribute) as? String == String(arguments[4].dropFirst(5)) }
        return attribute($0, kAXIdentifierAttribute) as? String == arguments[4]
    }) else {
        require(false, "identifier or role not found: \(arguments[4])"); exit(1)
    }
    require(AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, arguments[5] as CFString) == .success, "AXValue set failed")
    waitFor()
    print("set \(arguments[4]) = \(arguments[5])")
} else if action == "type" {
    require(arguments.count == 6, "usage: ax <pid> <bundle-id> type <AX-role> <text>")
    guard let element = find(root, matching: { attribute($0, kAXRoleAttribute) as? String == arguments[4] }) else {
        require(false, "text field not found"); exit(1)
    }
    _ = app.activate(options: [.activateAllWindows])
    require(AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success, "cannot focus text field")
    waitFor(0.2)
    let select = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    select.flags = .maskCommand
    select.postToPid(pid)
    let selectUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
    selectUp.flags = .maskCommand
    selectUp.postToPid(pid)
    if arguments[5].isEmpty {
        CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)?.postToPid(pid)
        CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)?.postToPid(pid)
    }
    for character in arguments[5] {
        var units = Array(String(character).utf16)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down.postToPid(pid)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)!
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        up.postToPid(pid)
    }
    waitFor(1)
    print("typed in \(arguments[4]): \(arguments[5])")
} else if action == "integrations" {
    _ = app.activate(options: [.activateAllWindows])
    waitFor()
    func press(_ element: AXUIElement?, _ description: String) {
        guard let element else { require(false, "missing \(description)"); exit(1) }
        require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "cannot press \(description)")
        print("action: \(description)")
        waitFor()
    }
    press(find(root) { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && labels($0).contains("Connection Settings") }, "Connection Settings")
    press(find(root) { attribute($0, kAXIdentifierAttribute) as? String == "manage-agent-integrations" }, "Manage Integrations")
    func expectRow(_ target: String, state: String) {
        for _ in 0..<60 {
            if let row = find(root, matching: { attribute($0, kAXIdentifierAttribute) as? String == "integration-row-\(target)" }),
               let data = try? JSONSerialization.data(withJSONObject: tree(row)),
               String(decoding: data, as: UTF8.self).contains(state) {
                print("result: \(target) = \(state)")
                return
            }
            waitFor(0.1)
        }
        require(false, "\(target) did not reach \(state)")
    }
    expectRow("codex", state: "Not Installed")
    press(find(root) { attribute($0, kAXIdentifierAttribute) as? String == "integration-install-codex" }, "Install Codex")
    expectRow("codex", state: "Up to Date")
    expectRow("claude", state: "Update Available")
    press(find(root) { attribute($0, kAXIdentifierAttribute) as? String == "integration-install-claude" }, "Update Claude Code")
    expectRow("claude", state: "Up to Date")
    press(find(root) { attribute($0, kAXIdentifierAttribute) as? String == "integration-remove-codex" }, "Remove Codex")
    expectRow("codex", state: "Not Installed")
    print("PASS: agent-integrations")
} else if action == "desktop-hooks" {
    _ = app.activate(options: [.activateAllWindows])
    waitFor()
    func press(_ element: AXUIElement?, _ description: String) {
        guard let element else { require(false, "missing \(description)"); exit(1) }
        require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "cannot press \(description)")
        print("action: \(description)")
        waitFor()
    }
    press(find(root) { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && labels($0).contains("Connection Settings") }, "Connection Settings")
    press(find(root) { attribute($0, kAXIdentifierAttribute) as? String == "manage-agent-integrations" }, "Manage Integrations")
    press(find(root) { [kAXRadioButtonRole, kAXButtonRole].contains(attribute($0, kAXRoleAttribute) as? String ?? "") && labels($0).contains("Desktop Clients") }, "Desktop Clients")
    func expect(_ source: String, label: String) -> AXUIElement {
        for _ in 0..<80 {
            if let button = find(root, matching: { attribute($0, kAXIdentifierAttribute) as? String == "desktop-hook-\(source)" && labels($0).contains(label) }),
               (attribute(button, kAXEnabledAttribute) as? NSNumber)?.boolValue == true { return button }
            waitFor(0.1)
        }
        require(false, "desktop hook \(source) never became \(label)")
        exit(1)
    }
    for source in ["claude", "codex", "cursor", "copilot"] {
        press(expect(source, label: "Install"), "Install \(source) desktop hook")
        _ = expect(source, label: "Remove")
        print("result: \(source) installed")
    }
    for source in ["claude", "codex", "cursor", "copilot"] {
        press(expect(source, label: "Remove"), "Remove \(source) desktop hook")
        _ = expect(source, label: "Install")
        print("result: \(source) removed")
    }
    print("PASS: desktop-hooks")
} else if action == "duration" {
    _ = app.activate(options: [.activateAllWindows])
    waitFor()
    func openSettings() -> AXUIElement {
        guard let button = find(root, matching: { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && labels($0).contains("Connection Settings") }) else {
            require(false, "Connection Settings toolbar button missing"); exit(1)
        }
        require(AXUIElementPerformAction(button, kAXPressAction as CFString) == .success, "cannot open settings")
        waitFor()
        guard let sheet = find(root, matching: { attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }) else {
            require(false, "settings sheet missing"); exit(1)
        }
        print("action: open Connection Settings; result: settings sheet")
        return sheet
    }
    func edit(_ sheet: AXUIElement, value: String, button: String) {
        guard let field = find(sheet, matching: { attribute($0, kAXIdentifierAttribute) as? String == "completion-window-minutes" }) else {
            require(false, "completion-window-minutes field missing"); exit(1)
        }
        require(AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, value as CFString) == .success, "cannot enter duration")
        guard let action = find(sheet, matching: { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && labels($0).contains(button) }) else {
            require(false, "\(button) button missing"); exit(1)
        }
        require(AXUIElementPerformAction(action, kAXPressAction as CFString) == .success, "cannot press \(button)")
        waitFor()
        print("action: enter \(value), press \(button); result: sheet closed")
        require(find(root, matching: { attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }) == nil, "sheet stayed open")
    }
    func storedMinutes() -> Int? {
        CFPreferencesAppSynchronize(arguments[2] as CFString)
        return (CFPreferencesCopyAppValue("completionWindowMinutes" as CFString, arguments[2] as CFString) as? NSNumber)?.intValue
    }
    edit(openSettings(), value: "7", button: "Save")
    require(storedMinutes() == 7, "saved duration is not 7")
    print("result: isolated preference completionWindowMinutes = 7")
    let sheet = openSettings()
    guard let field = find(sheet, matching: { attribute($0, kAXIdentifierAttribute) as? String == "completion-window-minutes" }) else {
        require(false, "duration field missing after reopen"); exit(1)
    }
    require((attribute(field, kAXValueAttribute) as? String) == "7", "reopened setting does not show 7")
    print("result: reopened duration field = 7")
    edit(sheet, value: "3", button: "Cancel")
    require(storedMinutes() == 7, "cancel changed persisted duration")
    print("result: cancelled edit left isolated preference at 7")
    print("PASS: settings-duration")
} else {
    require(false, "unknown action")
}
