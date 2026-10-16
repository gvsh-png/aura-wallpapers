import AVFoundation
import SwiftUI

/// Full-screen look at wallpapers before using them. ←/→ browse, Return sets, Esc or Space closes.
@MainActor
enum FullScreenPreview {
    private static var window: NSWindow?

    static func show(_ items: [Wallpaper], start: Wallpaper) {
        close(animated: false)
        guard !items.isEmpty, let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        let index = items.firstIndex { $0.id == start.id } ?? 0
        let w = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .statusBar
        w.backgroundColor = .black
        w.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: PreviewView(items: items, index: index, screen: screen)
            .environment(WallpaperEngine.shared))
        w.setFrame(screen.frame, display: true)
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; w.animator().alphaValue = 1 }
        window = w
    }

    static func close(animated: Bool = true) {
        guard let w = window else { return }
        window = nil
        guard animated else { w.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) })
    }

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }
}

private struct PreviewView: View {
    @Environment(WallpaperEngine.self) private var engine
    let items: [Wallpaper]
    @State var index: Int
    let screen: NSScreen
    @State private var chrome = true
    @State private var hideChrome: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var wallpaper: Wallpaper { items[index] }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            PreviewContent(wallpaper: wallpaper, screen: screen)
                .id(wallpaper.id)
                .transition(.opacity)
            if chrome { controls.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .ignoresSafeArea()
        .animation(.auraSpring, value: index)
        .animation(.auraSpring, value: chrome)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true; scheduleHide() }
        .onContinuousHover { _ in
            chrome = true
            scheduleHide()
        }
        .onKeyPress(.escape) { FullScreenPreview.close(); return .handled }
        .onKeyPress(.space) { FullScreenPreview.close(); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.return) { setWallpaper(); return .handled }
        .font(.aura(.body))
        .preferredColorScheme(.dark)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 18) }
                .buttonStyle(.glass).disabled(items.count < 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(wallpaper.title).font(.aura(.title3, .bold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(wallpaper.collection)
                    QualityTag(wallpaper: wallpaper)
                    if items.count > 1 { Text("\(index + 1) of \(items.count)").foregroundStyle(.secondary) }
                }
                .font(.aura(.callout))
            }
            .frame(minWidth: 220, alignment: .leading)
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 18) }
                .buttonStyle(.glass).disabled(items.count < 2)
            Divider().frame(height: 28)
            Button { setWallpaper() } label: {
                Label(engine.current?.id == wallpaper.id ? "On Your Desktop" : "Set as Wallpaper",
                      systemImage: engine.current?.id == wallpaper.id ? "checkmark.circle.fill" : "desktopcomputer")
            }
            .buttonStyle(.glassProminent)
            Button { FullScreenPreview.close() } label: { Label("Close", systemImage: "xmark") }
                .buttonStyle(.glass)
                .help("Esc")
        }
        .padding(14)
        .glass(cornerRadius: 20)
        .padding(.bottom, 36)
    }

    private func step(_ delta: Int) {
        guard items.count > 1 else { return }
        index = (index + delta + items.count) % items.count
    }

    private func setWallpaper() {
        let w = wallpaper
        Task { await engine.apply(w) }
    }

    private func scheduleHide() {
        hideChrome?.cancel()
        hideChrome = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { chrome = false }
        }
    }
}

/// The wallpaper at full screen resolution, scaled the way the desktop will show it.
private struct PreviewContent: View {
    let wallpaper: Wallpaper
    let screen: NSScreen
    @State private var image: NSImage?

    var body: some View {
        let scaling = Scaling.current
        Group {
            if wallpaper.kind == .live {
                LoopingVideo(url: wallpaper.url, gravity: scaling == .fill ? .resizeAspectFill : scaling == .fit ? .resizeAspect : .resize)
            } else if let image {
                switch scaling {
                case .fill: Image(nsImage: image).resizable().scaledToFill()
                case .fit: Image(nsImage: image).resizable().scaledToFit()
                case .stretch: Image(nsImage: image).resizable()
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: wallpaper.id) {
            guard wallpaper.kind == .still else { return }
            let pixels = Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor)
            let url = wallpaper.url
            let cg = await Task.detached { Images.downsample(url, maxPixel: pixels) }.value
            image = cg.map { NSImage(cgImage: $0, size: .zero) }
        }
    }
}

/// "4K", "1080p"… for a wallpaper, loaded lazily.
struct QualityTag: View {
    let wallpaper: Wallpaper
    var onCard = false
    @State private var size: CGSize?

    var body: some View {
        Group {
            if let size {
                let label = qualityLabel(size)
                if onCard {
                    Badge(text: label, tint: label == "SD" || label == "1080p" ? .orange.opacity(0.6) : .black.opacity(0.3))
                } else {
                    Text(label).font(.aura(.caption, .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
        }
        .task(id: wallpaper.id) { size = await Images.pixelSize(wallpaper) }
    }
}
