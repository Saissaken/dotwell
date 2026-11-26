// Renders the disk image window background: an arrow from the app to the Applications folder.
// Usage: swift scripts/dmg-background.swift <output-directory>
// Writes background.png (600x340) and background@2x.png; combine them with tiffutil.
import AppKit

// The window is 600x400 (scripts/dmg-settings.py); Finder's title and status bars take about 60 pt of it.
let size = NSSize(width: 600, height: 340)
// Icon centers as placed by scripts/dmg-settings.py, in Finder's top-left coordinates.
let appCenter = NSPoint(x: 150, y: 140)
let folderCenter = NSPoint(x: 450, y: 140)

func render(scale: CGFloat) -> Data? {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(
        starting: NSColor(calibratedWhite: 0.985, alpha: 1), ending: NSColor(calibratedWhite: 0.93, alpha: 1))?
        .draw(in: bounds, angle: -90)

    // Flip Finder's top-left coordinates into AppKit's bottom-left ones.
    let y = size.height - appCenter.y
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    let start = appCenter.x + 90
    let end = folderCenter.x - 90
    arrow.move(to: NSPoint(x: start, y: y))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.move(to: NSPoint(x: end - 14, y: y + 12))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.line(to: NSPoint(x: end - 14, y: y - 12))
    NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
    arrow.stroke()

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    func line(_ text: String, top: CGFloat, font: NSFont, white: CGFloat) {
        (text as NSString).draw(
            in: NSRect(x: 0, y: size.height - top - 20, width: size.width, height: 20),
            withAttributes: [
                .font: font, .foregroundColor: NSColor(calibratedWhite: white, alpha: 1), .paragraphStyle: style,
            ])
    }
    line("Drag Dotwell to Applications", top: 248, font: .systemFont(ofSize: 15, weight: .medium), white: 0.35)
    line(
        "If macOS blocks the first launch: System Settings › Privacy & Security › Open Anyway",
        top: 276, font: .systemFont(ofSize: 11), white: 0.5)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    guard let data = render(scale: scale) else { fatalError("could not render \(name)") }
    try data.write(to: output.appendingPathComponent(name))
}
