import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum WallpaperKind: String, CaseIterable, Identifiable {
    case still, live
    var id: String { rawValue }
    var title: String { self == .still ? "Static" : "Animated" }
    var symbol: String { self == .still ? "photo" : "play.rectangle.fill" }
}

/// One file in the library. Files are named "<Collection> - <Title>.<ext>".
struct Wallpaper: Identifiable, Hashable {
    let url: URL
    let kind: WallpaperKind
    let added: Date
    let size: Int64

    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    private var parts: [String] { name.components(separatedBy: " - ") }
    var collection: String { parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : "Unsorted" }
    var title: String { parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : name }

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tif", "tiff"]

    static func kind(forExtension ext: String) -> WallpaperKind? {
        let e = ext.lowercased()
        if videoExtensions.contains(e) { return .live }
        if imageExtensions.contains(e) { return .still }
        return nil
    }

    init?(url: URL) {
        guard let kind = Self.kind(forExtension: url.pathExtension) else { return nil }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        self.url = url
        self.kind = kind
        added = values?.creationDate ?? .distantPast
        size = Int64(values?.fileSize ?? 0)
    }
}

enum Prefs {
    // Theme
    static let autoTheme = "autoTheme"
    static let themeAccent = "themeAccent"
    static let themeHighlight = "themeHighlight"
    static let tintIcons = "tintIcons"
    static let tintStrength = "tintStrength"
    static let matchAppearance = "matchAppearance"
    // Playback
    static let animate = "animate"
    static let speed = "speed"
    static let scaling = "scaling"
    static let dim = "dim"
    static let sound = "sound"
    static let volume = "volume"
    // Power
    static let pauseWhenCovered = "pauseWhenCovered"
    static let pauseOnBattery = "pauseOnBattery"
    static let pauseInLowPower = "pauseInLowPower"
    // Rotation
    static let rotateMinutes = "rotateMinutes"
    static let rotateSource = "rotateSource"
    // App
    static let showMenuBarIcon = "showMenuBarIcon"
    static let autoUpdateCheck = "autoUpdateCheck"

    static func register() {
        UserDefaults.standard.register(defaults: [
            autoTheme: true, themeAccent: true, themeHighlight: true, tintIcons: true,
            tintStrength: TintStrength.balanced.rawValue, matchAppearance: false,
            animate: true, speed: 1.0, scaling: Scaling.fill.rawValue, dim: 0.0, sound: false, volume: 0.5,
            pauseWhenCovered: true, pauseOnBattery: false, pauseInLowPower: true,
            rotateMinutes: 0, rotateSource: RotateSource.all.rawValue,
            showMenuBarIcon: true, autoUpdateCheck: true,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }
}

enum Scaling: String, CaseIterable, Identifiable {
    case fill, fit, stretch
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    static var current: Scaling { Scaling(rawValue: Prefs.string(Prefs.scaling)) ?? .fill }
}

enum RotateSource: String, CaseIterable, Identifiable {
    case all, favorites, still, live
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All Wallpapers"
        case .favorites: "Favorites"
        case .still: "Static Only"
        case .live: "Animated Only"
        }
    }
    static var current: RotateSource { RotateSource(rawValue: Prefs.string(Prefs.rotateSource)) ?? .all }
}

enum TintStrength: String, CaseIterable, Identifiable {
    case subtle, balanced, vivid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    static var current: TintStrength { TintStrength(rawValue: Prefs.string(Prefs.tintStrength)) ?? .balanced }
}

enum Shell {
    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

enum Images {
    static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }

    static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    static func pixelSize(_ w: Wallpaper) async -> CGSize? {
        switch w.kind {
        case .still:
            guard let src = CGImageSourceCreateWithURL(w.url as CFURL, nil),
                  let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let pw = p[kCGImagePropertyPixelWidth] as? Int,
                  let ph = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
            return CGSize(width: pw, height: ph)
        case .live:
            guard let track = try? await AVURLAsset(url: w.url).loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize) else { return nil }
            return size
        }
    }

    /// A still frame for any wallpaper: the file itself for images, a cached poster frame for videos.
    static func stillURL(for w: Wallpaper) async -> URL? {
        w.kind == .still ? w.url : await Poster.make(for: w.url)
    }
}

enum Poster {
    static let folder = URL.cachesDirectory.appending(path: "Aura/Posters", directoryHint: .isDirectory)

    static func make(for video: URL) async -> URL? {
        let out = folder.appending(path: video.deletingPathExtension().lastPathComponent + ".jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        guard let frame = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image else { return nil }
        return Images.writeJPEG(frame, to: out) ? out : nil
    }
}

/// Starts Aura in the background at login via a user LaunchAgent.
enum LoginItem {
    static let label = "com.aura.wallpapers"
    static let plist = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist")

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func setEnabled(_ on: Bool) {
        guard on else { try? FileManager.default.removeItem(at: plist); return }
        guard let exe = Bundle.main.executableURL?.path else { return }
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dict: NSDictionary = ["Label": label, "ProgramArguments": [exe, "--background"], "RunAtLoad": true]
        dict.write(to: plist, atomically: true)
    }

    /// On by default. Rewrites the plist each launch so it follows the app if it moves.
    static func refresh() {
        if !UserDefaults.standard.bool(forKey: "loginConfigured") {
            UserDefaults.standard.set(true, forKey: "loginConfigured")
            setEnabled(true)
        } else if isEnabled {
            setEnabled(true)
        }
    }
}

extension NSColor {
    var srgb: NSColor { usingColorSpace(.sRGB) ?? self }
    var hex: String {
        let c = srgb
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

extension Int64 {
    var fileSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
