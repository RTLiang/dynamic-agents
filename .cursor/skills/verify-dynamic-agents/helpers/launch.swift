import AppKit
import Foundation

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.createsNewApplicationInstance = true
configuration.arguments = ["-AppleLanguages", "(en)", "-automaticallyCheckForUpdates", "NO"]
configuration.environment = ProcessInfo.processInfo.environment
let url = URL(fileURLWithPath: CommandLine.arguments[1])
Task { @MainActor in
    do {
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        print(app.processIdentifier)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Unable to launch verification app: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}
RunLoop.main.run()
