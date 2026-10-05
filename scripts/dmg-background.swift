import AppKit
import Foundation

// Installer-only artwork. The approved app icon master remains untouched.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let width: CGFloat = 680, height: CGFloat = 440
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color(0x10152C).setFill(); NSBezierPath(rect: rect(0, 0, width, height)).fill()
    // A quiet fan of the three fixed session colors above the installer.
    for (hex, top) in [(UInt32(0x34D766), CGFloat(6)), (0xFF9F0A, CGFloat(28)), (0xFF4D42, CGFloat(50))] {
        color(hex, alpha: 0.07).setFill()
        let beam = NSBezierPath(); beam.move(to: NSPoint(x: 415, y: height - 62))
        beam.line(to: NSPoint(x: width, y: height - top))
        beam.line(to: NSPoint(x: width, y: height - top - 16)); beam.close(); beam.fill()
    }
    func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, tint: NSColor) {
        let label = NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: tint])
        let dimensions = label.size()
        label.draw(at: NSPoint(x: (width - dimensions.width) / 2, y: height - top - dimensions.height))
    }
    text("Lightkeeper", top: 38, size: 32, weight: .semibold, tint: color(0xF6F7FF))
    text("Your AI sessions, within sight.", top: 84, size: 15, weight: .regular, tint: color(0xA9B3CF))
    for x in [CGFloat(90), CGFloat(420)] {
        color(0xFFFFFF, alpha: 0.035).setFill()
        NSBezierPath(roundedRect: rect(x, 137, 170, 174), xRadius: 24, yRadius: 24).fill()
        // Finder draws dark labels over image backgrounds, even in Dark Mode.
        color(0xE4E9F5).setFill()
        NSBezierPath(roundedRect: rect(x + 10, 277, 150, 28), xRadius: 10, yRadius: 10).fill()
    }
    color(0xFF9F0A).setStroke()
    let arrow = NSBezierPath(); arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 307, y: height - 210)); arrow.line(to: NSPoint(x: 373, y: height - 210))
    arrow.move(to: NSPoint(x: 360, y: height - 197)); arrow.line(to: NSPoint(x: 373, y: height - 210))
    arrow.line(to: NSPoint(x: 360, y: height - 223)); arrow.stroke()
    text("Drag Lightkeeper into Applications", top: 327, size: 18, weight: .medium, tint: color(0xF6F7FF))
    text("Then open it from your Applications folder.", top: 359, size: 13, weight: .regular, tint: color(0xA9B3CF))
    text("If macOS blocks opening: Privacy & Security → Open Anyway", top: 415, size: 11, weight: .regular, tint: color(0x8390B0))
    NSGraphicsContext.restoreGraphicsState()
    let filename = scale == 1 ? "DMGBackground.png" : "DMGBackground@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
