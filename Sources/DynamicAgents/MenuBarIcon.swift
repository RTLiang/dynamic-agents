import AppKit

@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let prompt = NSBezierPath()
            prompt.move(to: NSPoint(x: 3.5, y: 14.5))
            prompt.line(to: NSPoint(x: 9, y: 9))
            prompt.line(to: NSPoint(x: 3.5, y: 3.5))
            prompt.lineWidth = 2.4
            prompt.lineCapStyle = .round
            prompt.lineJoinStyle = .round
            prompt.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.5, y: 2.5, width: 3, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dynamic Agents"
        return image
    }()
}
