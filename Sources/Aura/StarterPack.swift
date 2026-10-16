import Foundation

/// A general-purpose pool of wallpapers. First launch (and Settings → Library → Download Starter Pack)
/// fetches a random handful: 1–4 static and 1–4 animated that aren't in the library yet.
/// Files are fetched from their sources, not bundled: wallhaven.cc (stills) and mixkit.co (Mixkit License videos).
enum StarterPack {
    struct Item {
        let collection: String
        let title: String
        let url: String
        var isAnimated: Bool { url.hasSuffix(".mp4") }
    }

    static let items: [Item] = [
        // Static
        Item(collection: "Landscapes", title: "Mountain lake sunrise", url: "https://w.wallhaven.cc/full/5y/wallhaven-5ymyz7.jpg"),
        Item(collection: "Landscapes", title: "Minimal peaks", url: "https://w.wallhaven.cc/full/ly/wallhaven-lyz3d2.png"),
        Item(collection: "Landscapes", title: "Forest lake at dusk", url: "https://w.wallhaven.cc/full/og/wallhaven-ogy6zm.jpg"),
        Item(collection: "Landscapes", title: "Autumn valley", url: "https://w.wallhaven.cc/full/yq/wallhaven-yqvj5g.jpg"),
        Item(collection: "Landscapes", title: "Mountain railway", url: "https://w.wallhaven.cc/full/yq/wallhaven-yqxzqx.jpg"),
        Item(collection: "Landscapes", title: "Cloudscape", url: "https://w.wallhaven.cc/full/e8/wallhaven-e89l8k.jpg"),
        Item(collection: "Nature", title: "Forest falls", url: "https://w.wallhaven.cc/full/gw/wallhaven-gwm2z3.jpg"),
        Item(collection: "Nature", title: "Autumn leaves", url: "https://w.wallhaven.cc/full/gw/wallhaven-gwwkql.jpg"),
        Item(collection: "Space", title: "Event horizon", url: "https://w.wallhaven.cc/full/po/wallhaven-pojl63.png"),
        Item(collection: "Space", title: "Warp speed", url: "https://w.wallhaven.cc/full/gw/wallhaven-gwpo6e.png"),
        Item(collection: "Space", title: "Crescent", url: "https://w.wallhaven.cc/full/8g/wallhaven-8g5qr2.png"),
        Item(collection: "Space", title: "Neon planet", url: "https://w.wallhaven.cc/full/k8/wallhaven-k81776.jpg"),
        Item(collection: "Abstract", title: "Wireframe horizon", url: "https://w.wallhaven.cc/full/ml/wallhaven-ml3jm8.jpg"),
        Item(collection: "Abstract", title: "Violet contours", url: "https://w.wallhaven.cc/full/ml/wallhaven-mlg7qm.png"),
        Item(collection: "Abstract", title: "Blue shards", url: "https://w.wallhaven.cc/full/w5/wallhaven-w5m6yr.jpg"),
        Item(collection: "Cities", title: "Snowy old town", url: "https://w.wallhaven.cc/full/og/wallhaven-ogyeol.jpg"),
        // Animated
        Item(collection: "Sky", title: "Aurora at dawn", url: "https://assets.mixkit.co/videos/4040/4040-1080.mp4"),
        Item(collection: "Sky", title: "Northern lights", url: "https://assets.mixkit.co/videos/4038/4038-1080.mp4"),
        Item(collection: "Sky", title: "Drifting clouds", url: "https://assets.mixkit.co/videos/51105/51105-1080.mp4"),
        Item(collection: "Sky", title: "Starry lake", url: "https://assets.mixkit.co/videos/1704/1704-1080.mp4"),
        Item(collection: "Water", title: "Beach waves", url: "https://assets.mixkit.co/videos/5016/5016-1080.mp4"),
        Item(collection: "Water", title: "Rain on a lake", url: "https://assets.mixkit.co/videos/18312/18312-1080.mp4"),
        Item(collection: "Water", title: "Rainy window", url: "https://assets.mixkit.co/videos/2846/2846-1080.mp4"),
        Item(collection: "Nature", title: "Forest waterfall", url: "https://assets.mixkit.co/videos/2213/2213-1080.mp4"),
        Item(collection: "Abstract", title: "Ink flow", url: "https://assets.mixkit.co/videos/44818/44818-1080.mp4"),
    ]

    /// Random 1–4 static and 1–4 animated items from the pool that the library doesn't have yet.
    static func pick(excluding have: Set<String>) -> [Item] {
        let missing = items.filter { !have.contains("\($0.collection) - \($0.title)") }
        let stills = missing.filter { !$0.isAnimated }.shuffled().prefix(Int.random(in: 1...4))
        let loops = missing.filter(\.isAnimated).shuffled().prefix(Int.random(in: 1...4))
        return Array(stills + loops)
    }

    /// Downloads a random pick. Returns how many arrived.
    @MainActor
    static func install() async -> Int {
        let picked = pick(excluding: Set(LibraryStore.shared.items.map(\.name)))
        return await withTaskGroup(of: Bool.self) { group in
            for item in picked {
                group.addTask { @MainActor in
                    guard let url = URL(string: item.url) else { return false }
                    return (try? await Downloader.fetch(url, collection: item.collection, title: item.title)) != nil
                }
            }
            var added = 0
            for await ok in group where ok { added += 1 }
            return added
        }
    }
}
