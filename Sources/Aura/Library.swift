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

    private init() { reload() }

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
    func setDesktop(_ w: Wallpaper) {
        current = w.id
        UserDefaults.standard.set(w.id, forKey: "current")
        Task {
            await DesktopFade.run { [url = w.url] in
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
                    ])
                }
            }
            let url = w.url
            let found: Palette? = await withCheckedContinuation { done in
                Thumbs.queue.async { done.resume(returning: Thumbs.diskThumbnail(url).flatMap(Palette.extract)) }
            }
            if let found { palette = found; found.save() }
        }
    }

    func shuffle(_ from: [Wallpaper]) {
        if let w = from.filter({ $0.id != current }).randomElement() ?? from.first { setDesktop(w) }
    }

    func trash(_ w: Wallpaper) {
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

/// Crossfade on the desktop: a window showing the old picture sits at desktop level (behind the icons)
/// while macOS swaps the picture underneath, then fades out and closes.
@MainActor enum DesktopFade {
    static func run(_ swap: @escaping () -> Void) async {
        let screens = NSScreen.screens.map { ($0, NSWorkspace.shared.desktopImageURL(for: $0), Int(max($0.frame.width, $0.frame.height) * $0.backingScaleFactor)) }
        // Decoded at screen size only for the length of the fade.
        let sources = screens.map { ($0.1, $0.2) }
        let olds: [CGImage?] = await withCheckedContinuation { done in
            Thumbs.queue.async { done.resume(returning: sources.map { s in s.0.flatMap { Thumbs.decode($0, maxPixel: s.1) } }) }
        }
        var windows: [NSWindow] = []
        for (i, (screen, _, _)) in screens.enumerated() {
            guard let old = olds[i] else { continue }
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            let view = NSView()
            view.wantsLayer = true
            view.layer?.contents = old
            view.layer?.contentsGravity = .resizeAspectFill
            w.contentView = view
            w.setFrame(screen.frame, display: true)
            w.orderFront(nil)
            windows.append(w)
        }
        swap()
        try? await Task.sleep(for: .milliseconds(350)) // let macOS draw the new picture first
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.9
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                windows.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { done.resume() })
        }
        windows.forEach { $0.orderOut(nil) }
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
    nonisolated static func diskThumbnail(_ url: URL) -> CGImage? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let thumb = diskFolder.appending(path: "\(url.deletingPathExtension().lastPathComponent)-\(size).jpg")
        if let hit = decode(thumb, maxPixel: 480) { return hit }
        guard let cg = decode(url, maxPixel: 480) else { return nil }
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
