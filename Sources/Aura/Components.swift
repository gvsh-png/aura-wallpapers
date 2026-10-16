import AVFoundation
import QuickLookThumbnailing
import SwiftUI

@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, size: CGFloat, token: Int64) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))#\(token)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size * 0.625), scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        cache.setObject(rep.nsImage, forKey: key)
        return rep.nsImage
    }
}

/// Fills its frame with a wallpaper thumbnail (images and videos alike).
struct Thumbnail: View {
    let wallpaper: Wallpaper
    var size: CGFloat = 520
    @State private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .task(id: "\(wallpaper.id)#\(wallpaper.size)") {
                let loaded = await ThumbnailCache.shared.image(for: wallpaper.url, size: size, token: wallpaper.size)
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
    }
}

/// Muted, looping video used for hover previews and the inspector.
struct LoopingVideo: NSViewRepresentable {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> PlayerView { PlayerView(url: url) }
    func updateNSView(_ view: PlayerView, context: Context) {
        view.load(url)
        (view.layer as? AVPlayerLayer)?.videoGravity = gravity
    }
    static func dismantleNSView(_ view: PlayerView, coordinator: ()) { view.player.pause() }

    final class PlayerView: NSView {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var url: URL?

        init(url: URL) {
            super.init(frame: .zero)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            self.layer = layer
            wantsLayer = true
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            load(url)
        }

        required init?(coder: NSCoder) { fatalError() }

        func load(_ url: URL) {
            guard url != self.url else { return }
            self.url = url
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }
    }
}

/// Blurred active wallpaper plus slow-drifting palette light, under a frosted layer the glass panels sit on.
struct Backdrop: View {
    @Environment(WallpaperEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let current = engine.current {
                Thumbnail(wallpaper: current, size: 320)
                    .blur(radius: 60)
                    .saturation(1.5)
                    .opacity(0.6)
                    .transition(.opacity)
            }
            AuroraLights(colors: engine.palette.map { $0.colors.prefix(3).map { Color(nsColor: $0) } } ?? [.indigo, .purple, .blue],
                         animated: !reduceMotion)
                .opacity(0.4)
            Rectangle().fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: engine.current?.id)
    }
}

/// Large blurred colour blobs from the palette. Static: it only animates when the colours change,
/// so an open window costs nothing per frame.
struct AuroraLights: View {
    let colors: [Color]
    let animated: Bool
    private let spots: [UnitPoint] = [.init(x: 0.2, y: 0.25), .init(x: 0.85, y: 0.35), .init(x: 0.45, y: 0.9)]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { i, color in
                    Circle()
                        .fill(color)
                        .frame(width: geo.size.width * 0.55, height: geo.size.width * 0.55)
                        .position(x: geo.size.width * spots[i].x, y: geo.size.height * spots[i].y)
                }
            }
            .blur(radius: 90)
            .drawingGroup()
        }
        .animation(animated ? .easeInOut(duration: 1.2) : nil, value: colors)
    }
}

/// Rounded glassy panel used across the app.
struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
    }
}

struct Badge: View {
    let text: String
    var symbol: String?
    var tint: Color = .black.opacity(0.3)

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.aura(size: 10, .bold))
        .textCase(.uppercase)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(tint.opacity(0.75))
            }
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

struct Swatch: View {
    let color: NSColor
    var size: CGFloat = 34
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(color.hex, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .overlay { if copied { Image(systemName: "checkmark").font(.aura(.caption, .bold)).foregroundStyle(.white).shadow(radius: 2) } }
                .shadow(color: Color(nsColor: color).opacity(0.5), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .help("\(color.hex) — click to copy")
    }
}

extension View {
    /// Selection/hover outline in the app tint.
    func cardOutline(selected: Bool, active: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .white.opacity(active ? 0.5 : 0.08), lineWidth: selected ? 3 : 1)
        )
    }
}

/// Empty/placeholder state in Geist (ContentUnavailableView forces the system font).
struct EmptyState<Actions: View>: View {
    let title: String
    let symbol: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.aura(.title2, .bold))
            Text(message).font(.aura(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(title: String, symbol: String, message: String) {
        self.init(title: title, symbol: symbol, message: message) { EmptyView() }
    }
}
