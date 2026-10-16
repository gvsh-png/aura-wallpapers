// Renders the Aura app icon (1024px PNG). Usage: swift make-icon.swift out.png
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(srgbRed: 0.55, green: 0.62, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.42, green: 0.36, blue: 0.92, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.12, blue: 0.40, alpha: 1),
    ])!.draw(in: shape, angle: -60)

    // Soft glow
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), .clear])!
        .draw(in: NSBezierPath(ovalIn: inset.offsetBy(dx: -180, dy: 220)), relativeCenterPosition: .zero)

    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
        .applying(.init(paletteColors: [.white, NSColor.white.withAlphaComponent(0.7)]))
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
    }
    NSColor.white.withAlphaComponent(0.18).setStroke()
    shape.lineWidth = 4
    shape.stroke()
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
