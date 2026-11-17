import AppKit
import SwiftUI

/// Matte black surfaces with a faint tint of the wallpaper's color, so the whole app follows it.
/// Views that read these re-render when the palette changes (Observation tracks the read).
@MainActor enum Matte {
    static var bg: Color { tinted(0.027, 0.035) }
    static var surface: Color { tinted(0.055, 0.05) }
    static var raised: Color { tinted(0.085, 0.06) }

    private static func tinted(_ v: Double, _ amount: Double) -> Color {
        let p = Library.shared.palette
        return Color(red: v + p.r * amount, green: v + p.g * amount, blue: v + p.b * amount)
    }
    static let line = Color.white.opacity(0.06)
    static let text = Color.white.opacity(0.94)
    static let dim = Color.white.opacity(0.48)
}

extension Font {
    /// Sora (SIL Open Font License), bundled in Resources/Fonts.
    static func sora(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Sora", size: size).weight(weight) }
}

extension Animation {
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.86)
}

/// The accent color for the current wallpaper.
struct Palette: Equatable {
    var r = 0.80, g = 0.78, b = 0.92
    var color: Color { Color(red: r, green: g, blue: b) }

    static func load() -> Palette {
        guard let a = UserDefaults.standard.array(forKey: "palette") as? [Double], a.count == 3 else { return Palette() }
        return Palette(r: a[0], g: a[1], b: a[2])
    }
    func save() { UserDefaults.standard.set([r, g, b], forKey: "palette") }

    /// Strongest color family in a small sample of the image, made bright enough to read on black.
    nonisolated static func extract(from image: CGImage) -> Palette? {
        let w = 48, h = 30
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var score = [Double](repeating: 0, count: 12)
        var sum = [(Double, Double, Double)](repeating: (0, 0, 0), count: 12)
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = NSColor(srgbRed: CGFloat(px[i]) / 255, green: CGFloat(px[i + 1]) / 255, blue: CGFloat(px[i + 2]) / 255, alpha: 1)
            let s = Double(c.saturationComponent), v = Double(c.brightnessComponent)
            guard s > 0.22, v > 0.2 else { continue }
            let bucket = min(11, Int(c.hueComponent * 12))
            let weight = s * v
            score[bucket] += weight
            sum[bucket].0 += Double(c.hueComponent) * weight
            sum[bucket].1 += s * weight
            sum[bucket].2 += v * weight
        }
        guard let best = score.indices.max(by: { score[$0] < score[$1] }), score[best] > 0 else { return nil }
        let n = score[best]
        let c = NSColor(hue: sum[best].0 / n, saturation: min(max(sum[best].1 / n, 0.45), 0.8), brightness: max(sum[best].2 / n, 0.88), alpha: 1)
        return Palette(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
    }
}

/// Matte black with a soft glow of the wallpaper's color at the top.
struct Backdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            Matte.bg
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .init(x: 0.5, y: -0.15), startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}

/// Pill buttons: matte, or filled with the accent when prominent.
struct MatteButton: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, prominent: prominent)
    }

    private struct Styled: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.sora(12.5, .medium))
                .padding(.horizontal, 14).frame(height: 30)
                .foregroundStyle(prominent ? AnyShapeStyle(Color.black) : AnyShapeStyle(Matte.text))
                .background(Capsule().fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(hover ? Matte.raised : Matte.surface)))
                .overlay(Capsule().strokeBorder(prominent ? .clear : Matte.line))
                .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.smooth, value: hover)
                .onHover { hover = $0 }
        }
    }
}

extension ButtonStyle where Self == MatteButton {
    static var matte: MatteButton { MatteButton() }
    static var accent: MatteButton { MatteButton(prominent: true) }
}

/// Round icon button for the header.
struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(Matte.text))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Circle().fill(hover ? Matte.raised : Matte.surface))
                .overlay(Circle().strokeBorder(Matte.line))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(.smooth, value: hover)
    }
}

/// Matte text field.
struct MatteField: View {
    let prompt: String
    @Binding var text: String
    var symbol = "magnifyingglass"
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Matte.dim).font(.system(size: 12))
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Matte.dim))
                .textFieldStyle(.plain)
                .font(.sora(13))
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(Matte.surface))
        .overlay(Capsule().strokeBorder(Matte.line))
    }
}

/// Carries the wallpaper's color into every app: the macOS accent color (nearest of the eight)
/// and the text highlight color. The user's own values are saved first and put back when turned off.
@MainActor enum SystemTheme {
    static let key = "matchSystemTheme"
    private static let keys = ["AppleAccentColor", "AppleHighlightColor"]
    private static let snapshotKey = "originalTheme"
    private static let absent = "__absent__"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }

    static func apply(_ p: Palette) {
        guard enabled else { return }
        remember()
        let c = NSColor(srgbRed: p.r, green: p.g, blue: p.b, alpha: 1)
        let index = accentIndex(c)
        if index == 4 {
            Shell.run("/usr/bin/defaults", ["delete", "-g", "AppleAccentColor"]) // Blue is the default
        } else {
            Shell.run("/usr/bin/defaults", ["write", "-g", "AppleAccentColor", "-int", String(index)])
        }
        let h = c.blended(withFraction: 0.45, of: .white)?.usingColorSpace(.sRGB) ?? c
        Shell.run("/usr/bin/defaults", ["write", "-g", "AppleHighlightColor", "-string",
                                        String(format: "%.6f %.6f %.6f Other", h.redComponent, h.greenComponent, h.blueComponent)])
        broadcast()
    }

    /// Puts back exactly what the user had before Aura changed it.
    static func restore() {
        var snapshot = UserDefaults.standard.dictionary(forKey: snapshotKey) ?? [:]
        for key in keys {
            guard let value = snapshot[key] else { continue }
            switch value {
            case let s as String where s != absent: Shell.run("/usr/bin/defaults", ["write", "-g", key, "-string", s])
            case let n as NSNumber: Shell.run("/usr/bin/defaults", ["write", "-g", key, "-int", String(n.intValue)])
            default: Shell.run("/usr/bin/defaults", ["delete", "-g", key])
            }
            snapshot[key] = nil
        }
        UserDefaults.standard.set(snapshot, forKey: snapshotKey)
        broadcast()
    }

    private static func remember() {
        var snapshot = UserDefaults.standard.dictionary(forKey: snapshotKey) ?? [:]
        guard keys.contains(where: { snapshot[$0] == nil }) else { return }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        for key in keys where snapshot[key] == nil {
            snapshot[key] = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) ?? absent as CFString
        }
        UserDefaults.standard.set(snapshot, forKey: snapshotKey)
    }

    /// Nearest macOS accent: -1 graphite, 0 red, 1 orange, 2 yellow, 3 green, 4 blue, 5 purple, 6 pink.
    static func accentIndex(_ c: NSColor) -> Int {
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

    private static func broadcast() {
        for name in ["AppleColorPreferencesChangedNotification", "AppleAquaColorVariantChanged"] {
            DistributedNotificationCenter.default().postNotificationName(.init(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}
