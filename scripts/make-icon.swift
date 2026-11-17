// Renders the Aura app icon (1024px PNG): a matte black tile with a glowing horizon,
// like light coming up behind a dark planet. Usage: swift make-icon.swift out.png
import AppKit

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)! }

// macOS icon grid: 824pt tile centered in 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(color(0.03, 0.03, 0.035))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Matte black, a touch lighter at the top.
ctx.drawLinearGradient(gradient([color(0.085, 0.085, 0.10), color(0.025, 0.025, 0.03)], [0, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// The planet: a big circle whose top edge is the horizon.
let center = CGPoint(x: 512, y: 250), radius: CGFloat = 360
let horizon = CGPoint(x: 512, y: center.y + radius)
let planet = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)

// Atmosphere glow above the horizon.
ctx.drawRadialGradient(gradient([color(0.82, 0.74, 1.00, 0.75), color(0.50, 0.48, 1.00, 0.22), color(0.35, 0.40, 1.00, 0)], [0, 0.35, 1]),
                       startCenter: horizon, startRadius: 0, endCenter: horizon, endRadius: 340, options: [])

// Planet body covers the lower half of the glow.
ctx.saveGState()
ctx.addPath(planet)
ctx.clip()
ctx.drawLinearGradient(gradient([color(0.06, 0.06, 0.075), color(0.015, 0.015, 0.02)], [0, 1]),
                       start: horizon, end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// Bright rim that fades toward the sides.
ctx.saveGState()
ctx.addPath(planet)
ctx.setLineWidth(11)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawRadialGradient(gradient([color(1, 0.97, 1, 1), color(0.72, 0.66, 1, 0.9), color(0.45, 0.55, 1, 0)], [0, 0.35, 1]),
                       startCenter: horizon, startRadius: 0, endCenter: horizon, endRadius: 400, options: [])
ctx.restoreGState()

// One small star.
let star = CGPoint(x: 700, y: 760)
ctx.drawRadialGradient(gradient([color(1, 1, 1, 0.9), color(0.8, 0.75, 1, 0)], [0, 1]),
                       startCenter: star, startRadius: 0, endCenter: star, endRadius: 13, options: [])
ctx.restoreGState()

// Hairline edge, brighter at the top like light on matte plastic.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.setLineWidth(3)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient([color(1, 1, 1, 0.16), color(1, 1, 1, 0.03)], [0, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
