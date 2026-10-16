import SwiftUI

// MARK: - Type

/// Geist (SIL OFL), bundled in Contents/Resources/Fonts and registered through ATSApplicationFontsPath.
enum AuraFont {
    static func face(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "Geist-Bold"
        case .semibold: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
    }

    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 28
        case .title: 22
        case .title2: 18
        case .title3: 15
        case .headline, .body: 13
        case .subheadline, .callout: 12
        case .footnote, .caption: 11
        default: 10
        }
    }
}

extension Font {
    static func aura(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        .custom(AuraFont.face(weight ?? (style == .headline ? .semibold : .regular)), size: AuraFont.size(style), relativeTo: style)
    }

    static func aura(size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(AuraFont.face(weight), size: size)
    }

    static func auraMono(_ style: Font.TextStyle) -> Font {
        .custom("GeistMono-Regular", size: AuraFont.size(style), relativeTo: style)
    }
}

// MARK: - Motion

extension Animation {
    static let auraSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let auraSnappy = Animation.spring(response: 0.26, dampingFraction: 0.72)
}

// MARK: - Glass

/// Frosted panel: material, faint tint, top sheen, light-catching edge and a soft drop shadow.
struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var shadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.14)) }
                    shape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.05), .white.opacity(0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadow ? 0.22 : 0), radius: 18, y: 10)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = 18, tint: Color? = nil, shadow: Bool = true) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }
}

/// Pill-shaped glass button. Prominent ones fill with the app tint.
struct GlassButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, prominent: prominent)
    }

    private struct GlassButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            configuration.label
                .font(.aura(.body, .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    ZStack {
                        if prominent { shape.fill(.tint) } else { shape.fill(.ultraThinMaterial) }
                        shape.fill(LinearGradient(colors: [.white.opacity(prominent ? 0.28 : 0.12), .clear], startPoint: .top, endPoint: .bottom))
                    }
                }
                .overlay(shape.strokeBorder(.white.opacity(prominent ? 0.32 : 0.16), lineWidth: 1))
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 12 : 6, y: hovering ? 6 : 3)
                .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? 1.015 : 1))
                .brightness(configuration.isPressed ? -0.06 : (hovering ? 0.03 : 0))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hovering = $0 && isEnabled }
                .animation(.auraSnappy, value: configuration.isPressed)
                .animation(.auraSpring, value: hovering)
        }
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
    static var glassProminent: GlassButtonStyle { GlassButtonStyle(prominent: true) }
}

// MARK: - Interactive tilt

/// Cards lean toward the pointer with a moving glare. Off when Reduce Motion is on.
struct TiltModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size: CGSize = .zero
    @State private var point: CGPoint?
    var maxDegrees: Double = 7
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let offset = point.map { CGSize(width: $0.x / max(size.width, 1) - 0.5, height: $0.y / max(size.height, 1) - 0.5) } ?? .zero
        content
            .overlay {
                if let point, !reduceMotion {
                    RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1)),
                                   startRadius: 0, endRadius: max(size.width, 1) * 0.7)
                        .blendMode(.plusLighter)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -offset.height * maxDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : offset.width * maxDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onContinuousHover { phase in
                withAnimation(.auraSpring) {
                    switch phase {
                    case .active(let p): point = p
                    case .ended: point = nil
                    }
                }
            }
    }
}

extension View {
    func tilt(_ maxDegrees: Double = 7) -> some View { modifier(TiltModifier(maxDegrees: maxDegrees)) }

    /// Fades and lifts in on first appearance, staggered by `index`.
    func appear(index: Int = 0) -> some View { modifier(AppearModifier(index: index)) }
}

struct AppearModifier: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                withAnimation(.auraSpring.delay(Double(index % 12) * 0.035)) { shown = true }
            }
    }
}
