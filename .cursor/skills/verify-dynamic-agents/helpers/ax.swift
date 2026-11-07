import AppKit
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? { var value: CFTypeRef?; AXUIElementCopyAttributeValue(element, key as CFString, &value); return value }
func all(_ element: AXUIElement, _ depth: Int = 0) -> [AXUIElement] {
    guard depth < 22, attribute(element, kAXRoleAttribute) as? String != kAXMenuBarRole else { return [] }
    return [element] + (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { all($0, depth + 1) }
}
func labels(_ element: AXUIElement) -> [String] { [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute].compactMap { attribute(element, $0) as? String } }
func tree(_ element: AXUIElement, _ depth: Int = 0) -> [String: Any] {
    var value: [String: Any] = ["role": attribute(element, kAXRoleAttribute) as? String ?? ""]
    for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute] {
        if let item = attribute(element, key) as? String { value[key] = item }
    }
    if depth < 18, attribute(element, kAXRoleAttribute) as? String != kAXMenuBarRole {
        value["children"] = (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { tree($0, depth + 1) }
    }
    return value
}
func require(_ condition: Bool, _ message: String) { if !condition { fputs("FAIL: " + message + "\n", stderr); exit(1) } }
func wait(_ seconds: Double = 0.25) { RunLoop.current.run(until: .now.addingTimeInterval(seconds)) }
let args = CommandLine.arguments
require(args.count >= 7, "ax <pid> <bundle> <action> <language> <scratch> <evidence>")
require(AXIsProcessTrusted(), "Accessibility permission is required for the verification tool")
require((CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool != true, "macOS session locked")
let pid = Int32(args[1])!
let bundle = args[2], action = args[3], language = args[4]
let scratch = URL(fileURLWithPath: args[5]), evidence = URL(fileURLWithPath: args[6])
let zh = language == "zh-Hans"
guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == bundle else { require(false, "wrong owned app"); exit(1) }
let root = AXUIElementCreateApplication(pid)
func node(_ id: String) -> AXUIElement? { all(root).first { attribute($0, kAXIdentifierAttribute) as? String == id } }
func save(_ name: String) { if let data = try? JSONSerialization.data(withJSONObject: tree(root), options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: evidence.appendingPathComponent(name + ".json")) } }
func press(_ element: AXUIElement?, _ name: String) {
    guard let element else { save("failed-ui"); require(false, "control missing: " + name); return }
    require(AXUIElementPerformAction(element, kAXPressAction as CFString) == .success, "press failed: " + name)
    wait()
    print("action: " + name)
}
func button(_ title: String) { press(all(root).first { attribute($0, kAXRoleAttribute) as? String == kAXButtonRole && labels($0).contains(title) }, title) }
func ready(_ id: String) -> AXUIElement? {
    for _ in 0..<50 {
        if let value = node(id), (attribute(value, kAXEnabledAttribute) as? NSNumber)?.boolValue != false { return value }
        wait(0.1)
    }
    return nil
}
func openHooks() { button(zh ? "设置" : "Settings"); press(ready("manage-agent-hooks"), "Manage Agent Hooks") }
func closeHooks() { button(zh ? "完成" : "Done"); button(zh ? "取消" : "Cancel"); wait(1.2) }
func strings() -> [String] { all(root).flatMap(labels) }
func checkRows(_ count: Int) {
    for _ in 0..<40 {
        if strings().contains(zh ? "\(count) 个 Agent" : "\(count) \(count == 1 ? "agent" : "agents")") { return }
        wait(0.1)
    }
    save("failed-row-count"); require(false, "expected \(count) agent rows")
}
func hostState() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.appendingPathComponent("host-state.json"))) as! [String: Any] }
func emit(_ events: [[String: Any]]) throws {
    let token = Int(Date.now.timeIntervalSince1970 * 1000)
    let data = try JSONSerialization.data(withJSONObject: ["token": token, "events": events])
    try data.write(to: scratch.appendingPathComponent("host-command.json"), options: .atomic)
    for _ in 0..<60 {
        if let state = try? hostState(), state["completedToken"] as? Int == token { require(state["error"] as? String == "", "fixture reporting failed"); return }
        wait(0.1)
    }
    require(false, "host fixture timeout")
}
if action == "doctor" {
    for _ in 0..<50 { if node("agents-table") != nil, (try? hostState()) != nil { break }; wait(0.1) }
    require(node("agents-table") != nil, "dashboard missing")
    checkRows(0)
    require(!strings().contains(where: { $0.localizedCaseInsensitiveContains("herdr") }), "removed integration leaked into UI")
    print("ready: empty hook-only dashboard and owned two-window host")
} else if action == "snapshot" {
    print(String(data: try JSONSerialization.data(withJSONObject: tree(root), options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
} else if action == "press" {
    require(args.count == 9, "press <role> <label>")
    press(all(root).first { attribute($0, kAXRoleAttribute) as? String == args[7] && labels($0).contains(args[8]) }, args[8])
} else if action == "hooks" {
    openHooks()
    let sources = ["pi", "claude", "codex", "cursor", "copilot"]
    for source in sources { press(ready("desktop-hook-" + source), "Install " + source) }
    let helper = scratch.appendingPathComponent("desktop-data/desktop-hook.py")
    var data = try Data(contentsOf: helper)
    data.append(Data("\n# previous helper\n".utf8)); try data.write(to: helper)
    press(ready("desktop-hooks-refresh"), "Refresh outdated state")
    for _ in 0..<30 { if node("desktop-hook-update-pi") != nil { break }; wait(0.1) }
    press(ready("desktop-hook-update-pi"), "Update shared helper")
    for _ in 0..<30 { if sources.allSatisfy({ node("desktop-hook-update-" + $0) == nil }) { break }; wait(0.1) }
    require(sources.allSatisfy { node("desktop-hook-update-" + $0) == nil }, "Update prompts did not clear")
    save("hooks-installed")
    closeHooks()
    try emit([
        ["source": "claude", "event": "UserPromptSubmit", "payload": ["session_id": "fixture-build", "cwd": "/example/Build example"]],
        ["source": "claude", "event": "SessionStart", "payload": ["session_id": "fixture-idle", "cwd": "/example/Review example"]]
    ])
    checkRows(2)
    let producer = Process()
    producer.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    producer.arguments = ["python3", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("desktop-fixture").path, scratch.lastPathComponent]
    try producer.run(); producer.waitUntilExit(); require(producer.terminationStatus == 0, "memory fixture failed")
    wait(1.2); checkRows(3)
    let values = strings()
    require(!values.contains("Background memory example") && !values.contains("Background legacy memory example"), "background sessions visible")
    guard let table = node("agents-table") else { exit(1) }
    let tableValues = all(table).flatMap(labels)
    guard let work = tableValues.firstIndex(of: "Build example"), let done = tableValues.firstIndex(of: "Memory project example"), let idle = tableValues.firstIndex(of: "Review example") else { require(false, "expected fixture sessions absent"); exit(1) }
    require(work < done && done < idle, "default row order is not Running, Completed, Idle")
    save("hooks-dashboard")
    guard let cell = all(table).first(where: { labels($0).contains("Build example") }) else { exit(1) }
    var row: AXUIElement? = cell
    for _ in 0..<12 {
        if row.flatMap({ attribute($0, kAXRoleAttribute) as? String }) == kAXRowRole { break }
        guard let current = row, let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { row = nil; break }
        row = (parent as! AXUIElement)
    }
    guard let row else { require(false, "fixture row unavailable"); exit(1) }
    let selected = AXUIElementSetAttributeValue(table, kAXSelectedRowsAttribute as CFString, [row] as CFArray)
    if selected != .success { require(AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success, "row selection failed") }
    wait()
    let before = try hostState()
    button(zh ? "打开 App" : "Open App")
    let hostPID = (before["pid"] as! NSNumber).int32Value
    for _ in 0..<30 { if NSWorkspace.shared.frontmostApplication?.processIdentifier == hostPID { break }; wait(0.1) }
    wait()
    let after = try hostState()
    require(NSWorkspace.shared.frontmostApplication?.processIdentifier == hostPID && !app.isActive, "wrong host app activated")
    require(before["lastKeyWindow"] as? String == after["lastKeyWindow"] as? String && after["windowCount"] as? Int == 2, "host window selection changed")
    try JSONSerialization.data(withJSONObject: ["before": before, "after": after, "passed": true], options: [.prettyPrinted]).write(to: evidence.appendingPathComponent("app-only-activation.json"))
    print("result: exact host app activated; its selected window and window count preserved")
    app.activate(); wait()
    openHooks()
    for source in sources { press(ready("desktop-hook-" + source), "Remove " + source) }
    save("hooks-removed")
    closeHooks(); checkRows(0)
    print("PASS: five hook adapters, helper update, user/memory filtering, row ordering and app-only activation")
} else if action == "settings" {
    button(zh ? "设置" : "Settings")
    guard let field = node("completion-window-minutes") else { exit(1) }
    require(AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "7" as CFString) == .success, "duration edit failed")
    button(zh ? "保存" : "Save")
    button(zh ? "设置" : "Settings")
    require(node("completion-window-minutes").flatMap { attribute($0, kAXValueAttribute) as? String } == "7", "saved duration missing")
    button(zh ? "取消" : "Cancel")
    print("PASS: hook-only settings Save/reopen/Cancel")
} else if action == "menu" {
    print("status item: " + (attribute(root, "AXExtrasMenuBar") == nil ? "absent" : "present"))
} else { require(false, "unknown action") }
