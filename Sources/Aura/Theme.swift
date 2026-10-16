import AppKit

struct Palette: Equatable {
    var colors: [NSColor]
    var accent: NSColor
    var isDark: Bool

    var css: String {
        colors.enumerated().map { "--aura-\($0.offset + 1): \($0.element.hex);" }.joined(separator: "\n")
            + "\n--aura-accent: \(accent.hex);"
    }
}

enum PaletteExtractor {
    static func extract(from w: Wallpaper) async -> Palette? {
        guard let still = await Images.stillURL(for: w) else { return nil }
        return await Task.detached(priority: .utility) { compute(still) }.value
    }

    /// Buckets a 96px thumbnail into 4-bit RGB cells, favours colourful cells, keeps up to 6 distinct ones.
    static func compute(_ url: URL) -> Palette? {
        guard let image = Images.downsample(url, maxPixel: 96) else { return nil }
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        struct Bucket { var n = 0, r = 0, g = 0, b = 0 }
        var buckets: [Int: Bucket] = [:]
        var luminance = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            var bucket = buckets[key] ?? Bucket()
            bucket.n += 1; bucket.r += r; bucket.g += g; bucket.b += b
            buckets[key] = bucket
            luminance += (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
        }

        let total = Double(w * h)
        let ranked = buckets.values.map { bk -> (color: NSColor, score: Double) in
            let n = CGFloat(bk.n) * 255
            let color = NSColor(srgbRed: CGFloat(bk.r) / n, green: CGFloat(bk.g) / n, blue: CGFloat(bk.b) / n, alpha: 1)
            let s = Double(color.saturationComponent), v = Double(color.brightnessComponent)
            let usable = (0.18...0.97).contains(v) ? 1.0 : 0.25
            return (color, Double(bk.n) / total * (0.3 + s * 1.7) * usable)
        }
        .sorted { $0.score > $1.score }

        var picked: [NSColor] = []
        for candidate in ranked where picked.count < 6 {
            if picked.allSatisfy({ distance($0, candidate.color) > 0.22 }) { picked.append(candidate.color) }
        }
        guard !picked.isEmpty else { return nil }
        let accent = picked.first { $0.saturationComponent > 0.25 && $0.brightnessComponent > 0.35 } ?? picked[0]
        return Palette(colors: picked, accent: accent, isDark: luminance / total < 0.5)
    }

    private static func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let dr = a.redComponent - b.redComponent, dg = a.greenComponent - b.greenComponent, db = a.blueComponent - b.blueComponent
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

/// Writes the palette into macOS: accent, text highlight, tinted app icons, light/dark. Each part has its own toggle.
enum ThemeManager {
    private static let defaults = "/usr/bin/defaults"
    private static let systemAccents = ["Graphite", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink"]

    static func accentIndex(_ color: NSColor) -> Int {
        let c = color.srgb
        if c.saturationComponent < 0.15 { return -1 }
        switch c.hueComponent * 360 {
        case ..<15: return 0
        case ..<45: return 1
        case ..<70: return 2
        case ..<165: return 3
        case ..<250: return 4
        case ..<300: return 5
        case ..<345: return 6
        default: return 0
        }
    }

    static func accentName(_ color: NSColor) -> String { systemAccents[accentIndex(color) + 1] }

    static func iconTint(_ color: NSColor) -> NSColor {
        let c = color.srgb
        let (s, b): (CGFloat, CGFloat) = switch TintStrength.current {
        case .subtle: (c.saturationComponent * 0.55, max(c.brightnessComponent, 0.7))
        case .balanced: (max(c.saturationComponent, 0.45), max(c.brightnessComponent, 0.75))
        case .vivid: (max(c.saturationComponent, 0.8), max(c.brightnessComponent, 0.9))
        }
        return NSColor(hue: c.hueComponent, saturation: s, brightness: b, alpha: 1).srgb
    }

    static func highlight(_ color: NSColor) -> NSColor { (color.srgb.blended(withFraction: 0.45, of: .white) ?? color).srgb }

    static func apply(_ p: Palette) {
        let c = p.accent.srgb
        if Prefs.bool(Prefs.themeAccent) {
            let index = accentIndex(c)
            if index == 4 {
                Shell.run(defaults, ["delete", "-g", "AppleAccentColor"]) // Blue is the default
            } else {
                Shell.run(defaults, ["write", "-g", "AppleAccentColor", "-int", String(index)])
            }
        }
        if Prefs.bool(Prefs.themeHighlight) {
            Shell.run(defaults, ["write", "-g", "AppleHighlightColor", "-string", "\(rgb(highlight(c))) Other"])
        }

        var dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if Prefs.bool(Prefs.matchAppearance), p.isDark != dark {
            NSAppleScript(source: "tell application \"System Events\" to tell appearance preferences to set dark mode to \(p.isDark)")?.executeAndReturnError(nil)
            dark = p.isDark
        }

        if Prefs.bool(Prefs.tintIcons) {
            let theme = dark ? "TintedDark" : "TintedLight"
            let tint = "\(rgb(iconTint(c))) 1.000000"
            Shell.run(defaults, ["write", "-g", "AppleIconAppearanceTheme", "-string", theme])
            Shell.run(defaults, ["write", "-g", "AppleIconAppearanceTintColor", "-string", "Other"])
            Shell.run(defaults, ["write", "-g", "AppleIconAppearanceCustomTintColor", "-string", tint])
            // Only bounce the Dock when the icons actually change.
            if UserDefaults.standard.string(forKey: "lastIconTint") != theme + tint {
                UserDefaults.standard.set(theme + tint, forKey: "lastIconTint")
                Shell.run("/usr/bin/killall", ["Dock"])
            }
        }
        broadcast()
    }

    static func reset() {
        resetAccent()
        resetHighlight()
        resetIcons()
    }

    static func resetAccent() {
        Shell.run(defaults, ["delete", "-g", "AppleAccentColor"])
        broadcast()
    }

    static func resetHighlight() {
        Shell.run(defaults, ["delete", "-g", "AppleHighlightColor"])
        broadcast()
    }

    static func resetIcons() {
        for key in ["AppleIconAppearanceTheme", "AppleIconAppearanceTintColor", "AppleIconAppearanceCustomTintColor"] {
            Shell.run(defaults, ["delete", "-g", key])
        }
        UserDefaults.standard.removeObject(forKey: "lastIconTint")
        Shell.run("/usr/bin/killall", ["Dock"])
    }

    private static func broadcast() {
        for name in ["AppleColorPreferencesChangedNotification", "AppleAquaColorVariantChanged", "AppleInterfaceThemeChangedNotification"] {
            DistributedNotificationCenter.default().postNotificationName(.init(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    private static func rgb(_ c: NSColor) -> String {
        String(format: "%.6f %.6f %.6f", c.redComponent, c.greenComponent, c.blueComponent)
    }
}
