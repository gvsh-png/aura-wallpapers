import AVFoundation

/// Animated wallpapers play from a cached hardware-HEVC copy sized and paced for a desktop
/// (≤ 4K or 1080p, ≤ 30 fps) instead of decoding a huge 60 fps original all day.
enum VideoOptimizer {
    static let folder = URL.cachesDirectory.appending(path: "Aura/Optimized", directoryHint: .isDirectory)
    private static let overridesKey = "videoQualityOverrides"

    /// Quality picked for this wallpaper in the inspector, else the Settings default.
    static func quality(for w: Wallpaper) -> VideoQuality {
        (UserDefaults.standard.dictionary(forKey: overridesKey)?[w.id] as? String).flatMap(VideoQuality.init) ?? .current
    }

    static func setQuality(_ quality: VideoQuality?, for w: Wallpaper) {
        var overrides = UserDefaults.standard.dictionary(forKey: overridesKey) ?? [:]
        overrides[w.id] = quality?.rawValue
        UserDefaults.standard.set(overrides, forKey: overridesKey)
    }

    static func cached(_ url: URL, quality: VideoQuality, cap30: Bool) -> URL? {
        let out = output(url, quality: quality, cap30: cap30)
        return FileManager.default.fileExists(atPath: out.path) ? out : nil
    }

    /// The file to play: a cached copy, a freshly made one, or the original when it already fits.
    static func playable(_ url: URL, quality: VideoQuality, cap30: Bool) async -> URL {
        if let hit = cached(url, quality: quality, cap30: cap30) { return hit }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let fps = try? await track.load(.nominalFrameRate) else { return url }
        let long = max(abs(size.width), abs(size.height))
        let preset: String? = switch quality {
        case .original: nil
        case .auto: long > 3900 ? AVAssetExportPresetHEVC3840x2160 : nil
        case .hd: long > 1950 ? AVAssetExportPresetHEVC1920x1080 : nil
        }
        let slowDown = cap30 && fps > 31
        guard preset != nil || slowDown else { return url }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset ?? AVAssetExportPresetHEVCHighestQuality) else { return url }
        if slowDown, let composition = try? await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset) {
            composition.frameDuration = CMTime(value: 1, timescale: 30)
            composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid // otherwise timing follows the 60 fps source
            session.videoComposition = composition
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = output(url, quality: quality, cap30: cap30)
        let partial = out.deletingPathExtension().appendingPathExtension("part.mov")
        try? FileManager.default.removeItem(at: partial)
        do {
            try await session.export(to: partial, as: .mov)
            try FileManager.default.moveItem(at: partial, to: out)
            return out
        } catch {
            try? FileManager.default.removeItem(at: partial)
            return url
        }
    }

    private static func output(_ url: URL, quality: VideoQuality, cap30: Bool) -> URL {
        folder.appending(path: "\(url.deletingPathExtension().lastPathComponent)-\(quality.rawValue)-\(cap30 ? "30" : "src").mov")
    }
}
