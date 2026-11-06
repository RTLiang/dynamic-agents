import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let developers = [ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
                  "/Applications/Xcode-beta.app/Contents/Developer", "/Applications/Xcode.app/Contents/Developer"].compactMap { $0 }
let tools = developers.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
}
guard let tool = tools.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
    fatalError("Icon Composer is required to export the app icon.")
}
let source = root.appendingPathComponent(".build/AppIcon.png")
let process = Process()
process.executableURL = tool
process.arguments = [root.appendingPathComponent("Resources/AppIcon.icon").path, "--export-image", "--output-file", source.path,
                     "--platform", "macOS", "--rendition", "Default", "--width", "1024", "--height", "1024", "--scale", "1"]
process.standardOutput = FileHandle.nullDevice
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0, let artwork = NSImage(contentsOf: source) else {
    fatalError("Icon Composer export failed.")
}
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let size = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    artwork.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
print(iconset.path)
