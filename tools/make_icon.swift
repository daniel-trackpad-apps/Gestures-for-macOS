import AppKit

_ = NSApplication.shared

func makeIcon() -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: 250, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
    return NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
        let r = rect.insetBy(dx: 40, dy: 40)
        let path = NSBezierPath(roundedRect: r, xRadius: 110, yRadius: 110)
        NSGradient(starting: .systemBlue, ending: .systemIndigo)?.draw(in: path, angle: -90)
        if let s = symbol {
            let w = s.size.width, h = s.size.height
            s.draw(in: NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h))
        }
        return true
    }
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let icon = makeIcon()
let sizes: [(Int, String)] = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                              (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                              (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]
for (px, name) in sizes {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
    }
}
