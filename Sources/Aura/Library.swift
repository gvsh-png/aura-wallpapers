import AppKit
import ImageIO
import Observation

/// One image in the library, named "<Collection> - <Title>.<ext>".
struct Wallpaper: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    private var parts: [String] { name.components(separatedBy: " - ") }
    var collection: String { parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : "Unsorted" }
    var title: String { parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : name }

    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tif", "tiff"]
}

/// The images in <folder>/Static (~/Pictures/Wallpapers unless the user picks another folder).
@MainActor @Observable
final class Library {
    static let shared = Library()
    nonisolated static let folderKey = "libraryFolder"
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/Wallpapers", directoryHint: .isDirectory)
    static var root: URL {
        guard let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty else { return defaultRoot }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    static var folder: URL { root.appending(path: "Static", directoryHint: .isDirectory) }

    private(set) var items: [Wallpaper] = []
    private(set) var folderPath = ""
    private(set) var current = UserDefaults.standard.string(forKey: "current")
    private(set) var palette = Palette.load()
    private(set) var favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])

    // Auto shuffle. While it's on, Aura stays running after its window closes.
    var autoShuffle = UserDefaults.standard.bool(forKey: "autoShuffle") {
        didSet { UserDefaults.standard.set(autoShuffle, forKey: "autoShuffle"); restartShuffle() }
    }
    var shuffleMinutes = UserDefaults.standard.object(forKey: "shuffleMinutes") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(shuffleMinutes, forKey: "shuffleMinutes"); restartShuffle() }
    }
    var shuffleFavoritesOnly = UserDefaults.standard.bool(forKey: "shuffleFavoritesOnly") {
        didSet { UserDefaults.standard.set(shuffleFavoritesOnly, forKey: "shuffleFavoritesOnly") }
    }
    private(set) var nextShuffle: Date? = UserDefaults.standard.object(forKey: "nextShuffle") as? Date
    @ObservationIgnored private var timer: Timer?

    private init() {
        reload()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Library.shared.tick() }
        }
        tick()
    }

    // MARK: Favorites

    func isFavorite(_ w: Wallpaper) -> Bool { favorites.contains(w.id) }

    func toggleFavorite(_ w: Wallpaper) {
        if favorites.remove(w.id) == nil { favorites.insert(w.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
    }

    var favoriteItems: [Wallpaper] { items.filter(isFavorite) }

    // MARK: Auto shuffle

    /// A new countdown from now, e.g. after the interval changes.
    private func restartShuffle() {
        nextShuffle = autoShuffle ? .now.addingTimeInterval(Double(shuffleMinutes) * 60) : nil
        UserDefaults.standard.set(nextShuffle, forKey: "nextShuffle")
        tick()
    }

    /// Changes the wallpaper if it's due, then sleeps until the next change. One timer, no polling.
    private func tick() {
        timer?.invalidate()
        guard autoShuffle else { return }
        if let next = nextShuffle, next > .now {
            timer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow, repeats: false) { _ in
                MainActor.assumeIsolated { Library.shared.tick() }
            }
            return
        }
        reload()
        let pool = shuffleFavoritesOnly && !favoriteItems.isEmpty ? favoriteItems : items
        shuffle(pool)
        restartShuffle()
    }

    /// Called on launch, when the app becomes active and after changes. No polling.
    func reload() {
        folderPath = (Self.root.path as NSString).abbreviatingWithTildeInPath
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let urls = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        let found = urls
            .filter { Wallpaper.extensions.contains($0.pathExtension.lowercased()) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map { Wallpaper(url: $0.0) }
        if found != items { items = found }
    }

    /// Fades from the old desktop picture to the new one, then picks the app's accent from it.
    /// Puts `w` on the desktop with the transition.
    func setDesktop(_ w: Wallpaper) {
        current = w.id
        UserDefaults.standard.set(w.id, forKey: "current")
        let url = w.url
        // The app (and, if turned on, macOS) shifts to the new color while the desktop transitions.
        Task {
            let found: Palette? = await withCheckedContinuation { done in
                Thumbs.queue.async { done.resume(returning: Thumbs.diskThumbnail(url).flatMap(Palette.extract)) }
            }
            if let found {
                palette = found
                found.save()
                SystemTheme.apply(found)
            }
        }
        Task {
            let swap = {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
                    ])
                }
            }
            if await DesktopTransition.show(url) { await DesktopTransition.commit(swap) }
        }
    }

    func shuffle(_ from: [Wallpaper]) {
        if let w = from.filter({ $0.id != current }).randomElement() ?? from.first { setDesktop(w) }
    }

    func trash(_ w: Wallpaper) {
        if favorites.remove(w.id) != nil { UserDefaults.standard.set(Array(favorites), forKey: "favorites") }
        NSWorkspace.shared.recycle([w.url]) { _, _ in Task { @MainActor in self.reload() } }
    }

    /// Copies the user's own images into the library. Returns how many arrived.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var count = 0
        for url in urls where Wallpaper.extensions.contains(url.pathExtension.lowercased()) {
            let dest = uniqueURL(base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.lowercased())
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { count += 1 }
        }
        reload()
        return count
    }

    /// nil goes back to ~/Pictures/Wallpapers.
    func changeFolder(to url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: Self.folderKey)
        reload()
    }

    func uniqueURL(base: String, ext: String) -> URL {
        var url = Self.folder.appending(path: "\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = Self.folder.appending(path: "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Wallpaper change on the desktop. The new picture comes in over the current one in windows just above
/// the desktop and below the icons: it fades in with a slight zoom settling to 1× and blur pulling into
/// focus. Only once it fully covers the screen does macOS get it (commit), then the windows go away.
/// Both show the same image filled the same way, so the hand-off is invisible.
@MainActor enum DesktopTransition {
    /// One window per screen for each picture shown; newest last. At most two sets live at once.
    private static var sets: [[NSWindow]] = []
    private static var generation = 0

    /// Covers the desktop with `url`. Returns false if a newer call took over.
    @discardableResult
    static func show(_ url: URL) async -> Bool {
        generation += 1
        let mine = generation
        let px = NSScreen.screens.map { Int(max($0.frame.width, $0.frame.height) * $0.backingScaleFactor) }.max() ?? 3000
        // Decoded at screen size, kept only while it's on screen.
        let image: CGImage? = await withCheckedContinuation { done in
            Thumbs.queue.async { done.resume(returning: Thumbs.decode(url, maxPixel: px)) }
        }
        guard mine == generation, let image else { return false }

        // Keep only the set on top to crossfade from; anything older is fully hidden by it anyway.
        while sets.count > 1 { sets.removeFirst().forEach { $0.orderOut(nil) } }
        let duration = 1.3
        sets.append(NSScreen.screens.map { window(image, on: $0, duration: duration) })

        try? await Task.sleep(for: .seconds(duration))
        guard mine == generation else { return false }
        while sets.count > 1 { sets.removeFirst().forEach { $0.orderOut(nil) } }
        return true
    }

    /// Hands the picture on screen to macOS, then uncovers it.
    static func commit(_ swap: () -> Void) async {
        let mine = generation
        swap()
        // Give macOS time to draw the new picture underneath before uncovering it.
        try? await Task.sleep(for: .seconds(1.2))
        guard mine == generation else { return }
        await fadeOut()
    }

    private static func fadeOut() async {
        let leaving = sets.flatMap { $0 }
        sets = []
        guard !leaving.isEmpty else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                leaving.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { done.resume() })
        }
        leaving.forEach { $0.orderOut(nil) }
    }

    private static func window(_ image: CGImage, on screen: NSScreen, duration: Double) -> NSWindow {
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        let layer = CALayer()
        layer.frame = view.bounds
        layer.contents = image
        layer.contentsGravity = .resizeAspectFill
        layer.contentsScale = screen.backingScaleFactor
        layer.masksToBounds = true
        view.layer?.addSublayer(layer)
        w.contentView = view
        w.setFrame(screen.frame, display: false)
        w.orderFront(nil)

        let ease = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        func animate(_ key: String, _ from: Any, _ to: Any, _ time: Double) {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = time
            a.timingFunction = ease
            layer.add(a, forKey: key)
        }
        let blur = CIFilter(name: "CIGaussianBlur")!
        blur.name = "blur"
        blur.setValue(0, forKey: kCIInputRadiusKey)
        layer.filters = [blur]
        animate("opacity", 0, 1, duration * 0.75)
        animate("transform.scale", 1.06, 1, duration)
        animate("filters.blur.inputRadius", 28, 0, duration * 0.9)
        return w
    }
}

/// Small decoded thumbnails, never the full image. The cache is capped and macOS can purge it.
@MainActor enum Thumbs {
    static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.totalCostLimit = 40_000_000 // ponytail: ~75 thumbnails at 480 px; raise if scrolling re-decodes too much
        return c
    }()

    nonisolated static let queue = DispatchQueue(label: "aura.thumbs", qos: .userInitiated)
    nonisolated static let diskFolder = URL.cachesDirectory.appending(path: "Aura/Thumbs", directoryHint: .isDirectory)

    nonisolated static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }

    /// Small JPEG on disk, made once. A big PNG can't be decoded at reduced size (6K needs ~95 MB),
    /// so that cost is paid only the first time a file is shown.
    nonisolated static func diskThumbnail(_ url: URL, maxPixel: Int = 480) -> CGImage? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let suffix = maxPixel == 480 ? "" : "-\(maxPixel)"
        let thumb = diskFolder.appending(path: "\(url.deletingPathExtension().lastPathComponent)-\(size)\(suffix).jpg")
        if let hit = decode(thumb, maxPixel: maxPixel) { return hit }
        guard let cg = decode(url, maxPixel: maxPixel) else { return nil }
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        writeJPEG(cg, to: thumb, quality: 0.8)
        return cg
    }

    @discardableResult
    nonisolated static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    static func image(for url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        // One decode at a time so big files never overlap in memory.
        let cg: CGImage? = await withCheckedContinuation { done in
            queue.async { done.resume(returning: diskThumbnail(url)) }
        }
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        cache.setObject(image, forKey: url as NSURL, cost: cg.width * cg.height * 4)
        return image
    }
}
