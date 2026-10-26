import AppKit

// Draws the app icon (a keycap with its homing bump on a blue squircle) into Resources/AppIcon.icns.
// Run: swift scripts/icon.swift
func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s), xRadius: r * s, yRadius: r * s)
    }
    // macOS icon grid: 824pt squircle centred on a 1024 canvas, soft drop shadow.
    let tile = rect(100, 100, 824, 824, 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.30, green: 0.45, blue: 1, alpha: 1), ending: NSColor(red: 0.13, green: 0.16, blue: 0.52, alpha: 1))!
        .draw(in: tile, angle: -90)
    // Keycap: lip, then face, then the F/J homing bump.
    NSColor(red: 0.62, green: 0.67, blue: 0.82, alpha: 1).setFill()
    rect(282, 252, 460, 460, 72).fill()
    NSGradient(starting: .white, ending: NSColor(red: 0.91, green: 0.93, blue: 0.97, alpha: 1))!
        .draw(in: rect(282, 286, 460, 460, 72), angle: -90)
    NSColor(red: 0.55, green: 0.60, blue: 0.75, alpha: 1).setFill()
    rect(452, 346, 120, 24, 12).fill()
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: set.appending(path: "icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: set.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try! FileManager.default.createDirectory(at: URL(filePath: "Resources"), withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(filePath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
