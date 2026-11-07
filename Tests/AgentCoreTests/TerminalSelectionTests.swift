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

@Test func selectedWindowDoesNotReuseAnotherWindowsAttachment() throws {
    let surfaces = [
        TerminalSurface(id: "selected", windowID: "window-b", tty: "/dev/ttys001"),
        TerminalSurface(id: "other", windowID: "window-a", tty: "/dev/ttys002")
    ]
    let target = try TerminalClientSelection.target(from: [selectedWindowClient, otherWindowAttachment], surfaces: surfaces, paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    #expect(target.client == selectedWindowClient)
    #expect(target.surface.windowID == "window-b")
    #expect(target.policy == .dedicatedAttachment)
}

@Test func repeatedOpeningReusesTheAttachmentWithinTheSelectedWindow() throws {
    let matching = TerminalClient(application: windowApp, processID: 42, tty: "/dev/ttys003", session: "default", attachedPaneID: "wA:p1")
    let surfaces = [
        TerminalSurface(id: "selected", windowID: "window-b", tty: "/dev/ttys001"),
        TerminalSurface(id: "other", windowID: "window-a", tty: "/dev/ttys002"),
        TerminalSurface(id: "matching", windowID: "window-b", tty: "/dev/ttys003")
    ]
    let target = try TerminalClientSelection.target(from: [selectedWindowClient, otherWindowAttachment, matching], surfaces: surfaces, paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    #expect(target.client == matching)
    #expect(target.policy == .existingAttachment)
    #expect(target.surface.id == "matching")
}

@Test func ambiguousAttachmentsInTheSelectedWindowRequireAnExplicitChoice() throws {
    let one = TerminalClient(application: windowApp, processID: 42, tty: "/dev/ttys003", session: "default", attachedPaneID: "wA:p1")
    let two = TerminalClient(application: windowApp, processID: 43, tty: "/dev/ttys004", session: "default", attachedPaneID: "wA:p1")
    let surfaces = [
        TerminalSurface(id: "selected", windowID: "window-b", tty: "/dev/ttys001"),
        TerminalSurface(id: "one", windowID: "window-b", tty: "/dev/ttys003"),
        TerminalSurface(id: "two", windowID: "window-b", tty: "/dev/ttys004")
    ]
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.target(from: [selectedWindowClient, one, two], surfaces: surfaces, paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    }
    let chosen = try TerminalClientSelection.target(from: [selectedWindowClient, one, two], surfaces: surfaces, paneID: "wA:p1", preferredBundleID: "", preferredClientID: two.id)
    #expect(chosen.client == two)
}

@Test func automaticSelectionStillReusesOneExistingAttachment() throws {
    let chosen = try TerminalClientSelection.client(from: [selectedWindowClient, otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: "")
    #expect(chosen == otherWindowAttachment)
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.client(from: [selectedWindowClient, otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "com.apple.Terminal", preferredClientID: selectedWindowClient.id)
    }
}

@Test func closedExplicitWindowIsNotReplacedByAnAttachmentElsewhere() {
    #expect(throws: HerdrError.self) {
        try TerminalClientSelection.client(from: [otherWindowAttachment], paneID: "wA:p1", preferredBundleID: "", preferredClientID: selectedWindowClient.id)
    }
}
