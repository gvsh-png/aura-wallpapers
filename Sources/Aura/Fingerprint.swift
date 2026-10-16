import AVFoundation
import CryptoKit
import ImageIO

/// Spots the same wallpaper twice: identical bytes, or the same picture re-encoded / resized.
struct Fingerprint {
    let sha: String?
    let dHash: UInt64?
    let aspect: Double?
    let duration: Double?

    static func make(_ w: Wallpaper) async -> Fingerprint {
        let still = await Images.stillURL(for: w)
        let duration: Double? = w.kind == .live
            ? (try? await AVURLAsset(url: w.url).load(.duration)).map(\.seconds)
            : nil
        return await Task.detached(priority: .utility) {
            let image = still.flatMap { Images.downsample($0, maxPixel: 256) }
            let size = Images.pixelSizeSync(still)
            return Fingerprint(sha: sha256(w.url),
                               dHash: image.map(dHash),
                               aspect: size.map { $0.width / max($0.height, 1) },
                               duration: duration)
        }.value
    }

    /// Exact copy, or perceptual hashes within 3 bits with matching shape (and length, for videos).
    func matches(_ other: Fingerprint) -> Bool {
        if let sha, sha == other.sha { return true }
        guard let a = dHash, let b = other.dHash, (a ^ b).nonzeroBitCount <= 3,
              let r1 = aspect, let r2 = other.aspect, abs(r1 - r2) / r2 < 0.03 else { return false }
        if duration != nil || other.duration != nil {
            guard let d1 = duration, let d2 = other.duration, abs(d1 - d2) < 1.5 else { return false }
        }
        return true
    }

    private static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 64-bit difference hash: 9×8 greyscale, one bit per left/right brightness step.
    private static func dHash(_ image: CGImage) -> UInt64 {
        var px = [UInt8](repeating: 0, count: 9 * 8)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        }
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 where px[y * 9 + x] < px[y * 9 + x + 1] {
                hash |= 1 << UInt64(y * 8 + x)
            }
        }
        return hash
    }
}
