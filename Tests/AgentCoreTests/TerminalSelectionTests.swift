import Foundation
import Testing
@testable import AgentCore

private let windowApp = TerminalApplication(pid: 10, bundleID: "com.mitchellh.ghostty", name: "Ghostty", path: "/Applications/Ghostty.app")
private let selectedWindowClient = TerminalClient(application: windowApp, processID: 40, tty: "/dev/ttys001", session: "default", attachedPaneID: nil)
private let otherWindowAttachment = TerminalClient(application: windowApp, processID: 41, tty: "/dev/ttys002", session: "default", attachedPaneID: "wA:p1")

@Test func explicitWindowSelectionOverridesAnAttachmentInAnotherWindow() throws {
    let selected = try TerminalClientSelection.client(from: [selectedWindowClient, otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    #expect(selected == selectedWindowClient)
}

@Test func selectedWindowNavigatesItsExistingClient() throws {
    let surfaces = [TerminalSurface(id: "selected", windowID: "window-b", tty: "/dev/ttys001"), TerminalSurface(id: "other", windowID: "window-a", tty: "/dev/ttys002")]
    let target = try TerminalClientSelection.target(from: [selectedWindowClient, otherWindowAttachment], surfaces: surfaces, paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    #expect(target.client == selectedWindowClient)
    #expect(target.surface.id == "selected")
    #expect(target.policy == .existingClient)
}

@Test func repeatedOpeningStaysInTheOriginalClientEvenWhenAnAttachmentExists() throws {
    let matching = TerminalClient(application: windowApp, processID: 42, tty: "/dev/ttys003", session: "default", attachedPaneID: "wA:p1")
    let surfaces = [TerminalSurface(id: "selected", windowID: "window-b", tty: "/dev/ttys001"), TerminalSurface(id: "matching", windowID: "window-b", tty: "/dev/ttys003")]
    for _ in 0..<2 {
        let target = try TerminalClientSelection.target(from: [selectedWindowClient, matching], surfaces: surfaces, paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
        #expect(target.client == selectedWindowClient)
        #expect(target.policy == .existingClient)
        #expect(target.surface.id == "selected")
    }
}

@Test func explicitAttachmentOnlyOpensItsOwnAgent() throws {
    let surface = TerminalSurface(id: "attached", windowID: "window-a", tty: "/dev/ttys002")
    let chosen = try TerminalClientSelection.target(from: [otherWindowAttachment], surfaces: [surface], paneID: "wA:p1", preferredBundleID: "", preferredClientID: otherWindowAttachment.id)
    #expect(chosen.policy == .existingAttachment)
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.target(from: [otherWindowAttachment], surfaces: [surface], paneID: "wB:p1", preferredBundleID: "", preferredClientID: otherWindowAttachment.id)
    }
}

@Test func automaticSelectionPrefersTheExistingHerdrInterface() throws {
    let chosen = try TerminalClientSelection.client(from: [selectedWindowClient, otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: "")
    #expect(chosen == selectedWindowClient)
    let fallback = try TerminalClientSelection.client(from: [otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: "")
    #expect(fallback == otherWindowAttachment)
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.client(from: [selectedWindowClient, otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "com.apple.Terminal", preferredClientID: selectedWindowClient.id)
    }
}

@Test func multipleExistingHerdrWindowsRequireAnExplicitChoice() {
    let second = TerminalClient(application: windowApp, processID: 44, tty: "/dev/ttys004", session: "default", attachedPaneID: nil)
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.client(from: [selectedWindowClient, second, otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: "")
    }
}

@Test func closedExplicitWindowIsNotReplacedByAnAttachmentElsewhere() {
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.client(from: [otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    }
}
