import Carbon.HIToolbox
import SwiftUI
import Observation

/// Quick picker in the style of Omarchy's switcher: a full-screen dark overlay with a coverflow of
/// wallpapers, the chosen one large in the middle. ←/→ browse, ↩ sets it, Esc closes.
/// Opens with ⌃⌥W from any app while Aura runs, or from the header.
@MainActor @Observable
final class Picker {
    static let shared = Picker()

    private(set) var items: [Wallpaper] = []
    private(set) var index = 0
    private(set) var isOpen = false
    /// The middle card at screen quality; the side cards use small thumbnails.
    private(set) var large: (id: String, image: NSImage)?
    @ObservationIgnored private var panel: PickerPanel?
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// The app that was in front, so focus goes back to it when the picker closes.
    @ObservationIgnored private var previousApp: NSRunningApplication?

    var selected: Wallpaper? { items.indices.contains(index) ? items[index] : nil }

    func toggle() { isOpen ? close(choose: false) : open() }

    func open() {
        let library = Library.shared
        library.reload()
        items = library.items
        guard !isOpen, !items.isEmpty, let screen = NSScreen.main else { return }
        index = items.firstIndex { $0.id == library.current } ?? 0
        loadLarge()
        prefetch()

        let panel = PickerPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .mainMenu + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PickerView().environment(self).environment(library))
        panel.setFrame(screen.frame, display: false)
        panel.onKey = { [weak self] code in self?.key(code) ?? false }
        panel.onResign = { [weak self] in self?.close(choose: false) }
        panel.alphaValue = 0
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        NSApp.activate() // keys only reach the panel while Aura is active
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        self.panel = panel
        isOpen = true
    }

    func select(_ i: Int) {
        guard items.indices.contains(i), i != index else { return }
        index = i
        loadLarge()
        prefetch()
    }

    /// Warms the thumbnail cache around the selection so fast browsing never shows empty cards.
    private func prefetch() {
        let around = items.indices.filter { abs($0 - index) <= 6 }.sorted { abs($0 - index) < abs($1 - index) }
        let urls = around.map { items[$0].url }
        Task { for url in urls { _ = await Thumbs.image(for: url) } }
    }

    func close(choose: Bool) {
        guard isOpen, let panel else { return }
        isOpen = false
        loading?.cancel()
        self.panel = nil
        panel.onResign = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }, completionHandler: { panel.contentView = nil; panel.close() })
        if choose, let w = selected, w.id != Library.shared.current { Library.shared.setDesktop(w) }
        items = []
        large = nil
        Thumbs.cache.removeAllObjects()
        previousApp?.activate()
        previousApp = nil
    }

    /// Decodes the middle card at screen quality after a short pause, so holding an arrow key stays light.
    private func loadLarge() {
        loading?.cancel()
        guard let w = selected else { return }
        loading = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let url = w.url
            let cg: CGImage? = await withCheckedContinuation { done in
                Thumbs.queue.async { done.resume(returning: Thumbs.diskThumbnail(url, maxPixel: 2200)) }
            }
            guard !Task.isCancelled, let cg else { return }
            large = (w.id, NSImage(cgImage: cg, size: .zero))
        }
    }

    private func key(_ code: UInt16) -> Bool {
        switch Int(code) {
        case kVK_LeftArrow, kVK_UpArrow: select(index - 1)
        case kVK_RightArrow, kVK_DownArrow, kVK_Tab: select(index + 1)
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: close(choose: true)
        case kVK_Escape: close(choose: false)
        default: return false
        }
        return true
    }
}

/// Borderless full-screen panel that takes the keys.
final class PickerPanel: NSPanel {
    var onKey: ((UInt16) -> Bool)?
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    // Keys are taken here, before the SwiftUI views can turn Esc/Return into other commands.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event.keyCode) == true { return }
        super.sendEvent(event)
    }
    override func resignKey() { super.resignKey(); onResign?() } // switching away closes it
}

struct PickerView: View {
    @Environment(Picker.self) private var picker
    @Environment(Library.self) private var library

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.5, (geo.size.height * 0.55) * Thumbnail.screenAspect)
            ZStack {
                Color.black.opacity(0.86)
                    .overlay(RadialGradient(colors: [library.palette.color.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.6))
                    .ignoresSafeArea()
                    .onTapGesture { picker.close(choose: false) }

                ForEach(visible, id: \.1.id) { i, w in
                    card(w, offset: i - picker.index, width: cardWidth)
                }

                VStack(spacing: 6) {
                    Spacer()
                    if let w = picker.selected {
                        Text(w.title).font(.sora(40, .semibold)).lineLimit(1)
                            .contentTransition(.opacity)
                        Text("\(w.collection)  ·  \(picker.index + 1) of \(picker.items.count)").font(.sora(14)).foregroundStyle(Matte.dim)
                    }
                    Text("←  →  browse      ↩  set      esc  close").font(.sora(12, .medium)).foregroundStyle(Matte.dim.opacity(0.7))
                        .padding(.top, 22)
                }
                .padding(.bottom, max(40, geo.size.height * 0.08))

                HStack {
                    arrow("chevron.left") { picker.select(picker.index - 1) }
                    Spacer()
                    arrow("chevron.right") { picker.select(picker.index + 1) }
                }
                .padding(.horizontal, 28)
            }
            .offset(y: -geo.size.height * 0.04)
        }
        .foregroundStyle(Matte.text)
        .tint(library.palette.color)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: picker.index) // snappy, retargets cleanly on fast key repeats
        .preferredColorScheme(.dark)
    }

    /// The selected card and up to four on each side.
    private var visible: [(Int, Wallpaper)] {
        let lo = max(0, picker.index - 4), hi = min(picker.items.count - 1, picker.index + 4)
        return lo <= hi ? (lo...hi).map { ($0, picker.items[$0]) } : []
    }

    private func card(_ w: Wallpaper, offset d: Int, width: CGFloat) -> some View {
        let side = Double(d.signum()), n = Double(abs(d))
        let x = d == 0 ? 0 : side * (width * 0.56 + (n - 1) * width * 0.17)
        // Screen-shaped like the desktop, filled and cropped, never stretched by the picture's own shape.
        return Thumbnail(url: w.url, corner: 14)
            .frame(width: width, height: width / Thumbnail.screenAspect)
            .overlay {
                if let large = picker.large, large.id == w.id {
                    Image(nsImage: large.image).resizable().scaledToFill()
                        .frame(width: width, height: width / Thumbnail.screenAspect)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity)
                }
            }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(d == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(Matte.line), lineWidth: d == 0 ? 3 : 1))
        .overlay { RoundedRectangle(cornerRadius: 14).fill(.black.opacity(d == 0 ? 0 : 0.35 + 0.08 * n)) }
        .shadow(color: .black.opacity(d == 0 ? 0.7 : 0), radius: 36, y: 18)
        .rotation3DEffect(.degrees(-side * 38), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .scaleEffect(d == 0 ? 1 : max(0.4, 0.66 - (n - 1) * 0.07))
        .offset(x: x)
        .opacity(n > 3 ? 0 : 1)
        .zIndex(-n)
        .onTapGesture { d == 0 ? picker.close(choose: true) : picker.select(picker.index + d) }
        .animation(.easeOut(duration: 0.3), value: picker.large?.id)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(Matte.surface.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Matte.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// ⌃⌥W from any app. Carbon hot keys need no Accessibility permission.
enum HotKey {
    static func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { Picker.shared.toggle() } }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x41555241, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
