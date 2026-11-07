import AppKit
#if SWIFT_PACKAGE
import AgentCore
#endif

@MainActor
enum TerminalAutomation {
    private static func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: "with timeout of 5 seconds\n" + source + "\nend timeout") else {
            throw HerdrError.message(L10n.text("Unable to prepare terminal automation."))
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw HerdrError.message(L10n.format("Terminal automation failed: %@", error[NSAppleScript.errorMessage] as? String ?? "Apple Event error"))
        }
        return result.stringValue ?? ""
    }

    private static func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }

    private static func validate(_ application: TerminalApplication) throws {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleID)
        guard instances.count == 1, instances[0].processIdentifier == application.pid else {
            throw HerdrError.message(L10n.text("The terminal app instance has changed or is ambiguous. Refresh before selecting its window."))
        }
    }

    static func surfaces(in application: TerminalApplication) throws -> [TerminalSurface] {
        try validate(application)
        let source: String
        switch application.bundleID {
        case "com.mitchellh.ghostty":
            source = """
            tell application id "com.mitchellh.ghostty"
                set output to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in terminals of t
                            set output to output & (id of s as text) & tab & (id of w as text) & tab & (tty of s as text) & tab & (pid of s as text) & linefeed
                        end repeat
                    end repeat
                end repeat
                return output
            end tell
            """
        case "com.apple.Terminal":
            source = """
            tell application id "com.apple.Terminal"
                set output to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set output to output & (tty of t as text) & tab & (id of w as text) & tab & (tty of t as text) & tab & "0" & linefeed
                    end repeat
                end repeat
                return output
            end tell
            """
        case "com.googlecode.iterm2":
            source = """
            tell application id "com.googlecode.iterm2"
                set output to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set output to output & (id of s as text) & tab & (id of w as text) & tab & (tty of s as text) & tab & "0" & linefeed
                        end repeat
                    end repeat
                end repeat
                return output
            end tell
            """
        default:
            throw HerdrError.message(L10n.text("Exact window focus requires Ghostty 1.3 or later, iTerm2, or Apple Terminal. Other terminals will not be activated speculatively."))
        }
        return try run(source).split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4 else { return nil }
            return TerminalSurface(id: fields[0], windowID: fields[1], tty: fields[2], processID: Int32(fields[3]))
        }
    }

    static func focusedSurfaceID(in application: TerminalApplication) throws -> String {
        try validate(application)
        switch application.bundleID {
        case "com.mitchellh.ghostty":
            return try run("tell application id \"com.mitchellh.ghostty\" to return id of focused terminal of selected tab of front window")
        case "com.apple.Terminal":
            return try run("tell application id \"com.apple.Terminal\" to return tty of selected tab of front window")
        case "com.googlecode.iterm2":
            return try run("tell application id \"com.googlecode.iterm2\" to return id of current session of current tab of current window")
        default: throw HerdrError.message(L10n.text("This terminal does not support exact window focus."))
        }
    }

    static func focus(_ surface: TerminalSurface, application: TerminalApplication) throws {
        try validate(application)
        switch application.bundleID {
        case "com.mitchellh.ghostty":
            _ = try run("""
            tell application id "com.mitchellh.ghostty"
                set targetTerminal to first terminal whose id is \(literal(surface.id))
                focus targetTerminal
            end tell
            """)
        case "com.apple.Terminal":
            _ = try run("""
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    if (id of w as text) is \(literal(surface.windowID)) then
                        repeat with t in tabs of w
                            if (tty of t as text) is \(literal(surface.tty)) then
                                set selected tab of w to t
                                set miniaturized of w to false
                                set index of w to 1
                                activate
                                return "focused"
                            end if
                        end repeat
                    end if
                end repeat
                error "Terminal tab no longer exists"
            end tell
            """)
        case "com.googlecode.iterm2":
            _ = try run("""
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    if (id of w as text) is \(literal(surface.windowID)) then
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if (id of s as text) is \(literal(surface.id)) then
                                    select t
                                    select s
                                    set miniaturized of w to false
                                    set index of w to 1
                                    activate
                                    return "focused"
                                end if
                            end repeat
                        end repeat
                    end if
                end repeat
                error "Terminal session no longer exists"
            end tell
            """)
        default: throw HerdrError.message(L10n.text("This terminal does not support exact window focus."))
        }
    }

    static func attach(paneID: String, executable: String, session: String, in surface: TerminalSurface, application: TerminalApplication) throws {
        try validate(application)
        let argv = [executable, "--session", session.isEmpty ? "default" : session, "agent", "attach", paneID]
        let command = argv.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        switch application.bundleID {
        case "com.mitchellh.ghostty":
            _ = try run("""
            tell application id "com.mitchellh.ghostty"
                set targetWindow to first window whose id is \(literal(surface.windowID))
                set configuration to new surface configuration
                set command of configuration to \(literal(command))
                set createdTab to new tab in targetWindow with configuration configuration
                focus (focused terminal of createdTab)
            end tell
            """)
        case "com.apple.Terminal":
            _ = try run("""
            tell application id "com.apple.Terminal"
                do script \(literal(command))
                activate
            end tell
            """)
        case "com.googlecode.iterm2":
            guard let windowID = Int(surface.windowID) else { throw HerdrError.message(L10n.text("This terminal does not support exact window focus.")) }
            _ = try run("""
            tell application id "com.googlecode.iterm2"
                set targetWindow to first window whose id is \(windowID)
                tell targetWindow
                    set createdTab to create tab with default profile command \(literal(command))
                end tell
                select createdTab
                activate
            end tell
            """)
        default: throw HerdrError.message(L10n.text("This terminal does not support exact window focus."))
        }
    }
}
