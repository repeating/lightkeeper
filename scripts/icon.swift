import AppKit
import Foundation

// Optional iconset helper. The approved Lighthouse PNG/SVG remain untouched.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = project.appendingPathComponent("assets/SessionBeacon-icon.png")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: source) else { fatalError("Missing approved icon: \(source.path)") }
let output = NSImage(size: NSSize(width: 1024, height: 1024))
output.lockFocus()
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
output.unlockFocus()
let bitmap = NSBitmapImageRep(data: output.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_512x512@2x.png"))
