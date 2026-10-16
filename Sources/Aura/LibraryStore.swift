import AppKit
import Observation

/// The wallpaper library: ~/Pictures/Wallpapers/{Static,Live}. Agents drop files there too.
@MainActor @Observable
final class LibraryStore {
    static let shared = LibraryStore()
    nonisolated static let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/Wallpapers", directoryHint: .isDirectory)
    nonisolated static func folder(for kind: WallpaperKind) -> URL {
        root.appending(path: kind == .still ? "Static" : "Live", directoryHint: .isDirectory)
    }

    private(set) var items: [Wallpaper] = []
    /// Files that showed up after launch (agent downloads, imports). Cleared when the user dismisses them.
    var newArrivals: Set<String> = []
    private(set) var favorites: Set<String>
    private(set) var installingStarter = false
    /// Duplicates Aura moved to the Trash this session (agent downloads, imports, starter pack).
    private(set) var duplicatesRemoved = 0

    @ObservationIgnored private var known: Set<String>?
    @ObservationIgnored private var fingerprints: [String: Fingerprint] = [:] // "path#size"
    @ObservationIgnored private var settling: [String: Int64] = [:]
    @ObservationIgnored private var checked: Set<String> = []
    @ObservationIgnored private var timer: Timer?

    private init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        for kind in WallpaperKind.allCases {
            try? FileManager.default.createDirectory(at: Self.folder(for: kind), withIntermediateDirectories: true)
        }
        AgentDocs.install()
        reload()
        // ponytail: 2s folder poll; move to FSEvents if libraries grow into the thousands
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var collections: [(name: String, count: Int)] {
        Dictionary(grouping: items, by: \.collection)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func reload() {
        let fm = FileManager.default
        let found = WallpaperKind.allCases.flatMap { kind in
            ((try? fm.contentsOfDirectory(at: Self.folder(for: kind), includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles)) ?? [])
                .compactMap(Wallpaper.init(url:))
                .filter { $0.size > 20_000 } // skip downloads that just started
        }
        .sorted { $0.added > $1.added }

        let ids = Set(found.map(\.id))
        if let known { newArrivals.formUnion(ids.subtracting(known)) }
        newArrivals.formIntersection(ids)
        known = ids
        if found != items { items = found }
        checkNewArrivalsForDuplicates()
    }

    // MARK: - Duplicates

    /// Once a new file stops growing (two polls with the same size), compare it with the rest of the library.
    private func checkNewArrivalsForDuplicates() {
        for w in items where newArrivals.contains(w.id) && !checked.contains(w.id) {
            guard settling[w.id] == w.size else { settling[w.id] = w.size; continue }
            settling[w.id] = nil
            checked.insert(w.id)
            // Compare with everything except other downloads that are still in flight.
            let unsettled = newArrivals.subtracting(checked)
            let others = items.filter { $0.id != w.id && $0.kind == w.kind && !unsettled.contains($0.id) }
            Task {
                let mine = await fingerprint(w)
                for other in others where await fingerprint(other).matches(mine) {
                    removeDuplicate(w)
                    return
                }
            }
        }
    }

    /// One pass over the whole library. In each group of copies it keeps the wallpaper on the desktop,
    /// then a favorite, then the oldest file; the rest go to the Trash.
    func removeExistingDuplicates() async {
        var kept: [(Wallpaper, Fingerprint)] = []
        let current = WallpaperEngine.shared.current?.id
        let ordered = items.sorted { a, b in
            let ra = (a.id == current ? 0 : isFavorite(a) ? 1 : 2), rb = (b.id == current ? 0 : isFavorite(b) ? 1 : 2)
            return ra != rb ? ra < rb : a.added < b.added
        }
        for w in ordered {
            let print = await fingerprint(w)
            if kept.contains(where: { $0.0.kind == w.kind && $0.1.matches(print) }) {
                removeDuplicate(w)
            } else {
                kept.append((w, print))
            }
        }
    }

    private func removeDuplicate(_ w: Wallpaper) {
        newArrivals.remove(w.id)
        duplicatesRemoved += 1
        NSWorkspace.shared.recycle([w.url]) { _, _ in Task { @MainActor in self.reload() } }
    }

    private func fingerprint(_ w: Wallpaper) async -> Fingerprint {
        let key = "\(w.id)#\(w.size)"
        if let hit = fingerprints[key] { return hit }
        let made = await Fingerprint.make(w)
        fingerprints[key] = made
        return made
    }

    func installStarterPack() {
        guard !installingStarter else { return }
        installingStarter = true
        Task {
            _ = await StarterPack.install()
            installingStarter = false
        }
    }

    func isFavorite(_ w: Wallpaper) -> Bool { favorites.contains(w.id) }

    func toggleFavorite(_ w: Wallpaper) {
        if favorites.remove(w.id) == nil { favorites.insert(w.id) }
        saveFavorites()
    }

    private func saveFavorites() { UserDefaults.standard.set(Array(favorites), forKey: "favorites") }

    func trash(_ ws: [Wallpaper]) {
        if let current = WallpaperEngine.shared.current, ws.contains(where: { $0.id == current.id }) {
            WallpaperEngine.shared.turnOff()
        }
        NSWorkspace.shared.recycle(ws.map(\.url)) { _, _ in
            Task { @MainActor in self.reload() }
        }
    }

    @discardableResult
    func rename(_ w: Wallpaper, collection: String, title: String) -> Wallpaper? {
        let c = Self.sanitize(collection), t = Self.sanitize(title)
        let base = c.isEmpty ? (t.isEmpty ? w.name : t) : "\(c) - \(t.isEmpty ? "Untitled" : t)"
        guard base != w.name else { return w }
        let dest = uniqueURL(in: w.url.deletingLastPathComponent(), base: base, ext: w.url.pathExtension)
        guard (try? FileManager.default.moveItem(at: w.url, to: dest)) != nil else { return nil }
        known?.insert(dest.path) // a rename is not a new arrival
        if favorites.remove(w.id) != nil { favorites.insert(dest.path); saveFavorites() }
        reload()
        let renamed = Wallpaper(url: dest)
        if let renamed, WallpaperEngine.shared.current?.id == w.id { WallpaperEngine.shared.adoptRenamed(renamed) }
        return renamed
    }

    /// Copies images, videos and the contents of .zip packs into the library. Returns how many arrived.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var count = 0
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                guard Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, tmp.path]) == 0 else { continue }
                let inner = (FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
                count += importFiles(inner.filter { !$0.path.contains("__MACOSX") })
                continue
            }
            guard let kind = Wallpaper.kind(forExtension: url.pathExtension) else { continue }
            let dest = uniqueURL(in: Self.folder(for: kind), base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension.lowercased())
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { count += 1 }
        }
        reload()
        return count
    }

    /// Zips wallpapers into a shareable pack that Aura (or anyone) can open.
    nonisolated static func exportPack(_ urls: [URL], to dest: URL) -> Bool {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: UUID().uuidString).appending(path: dest.deletingPathExtension().lastPathComponent)
        guard (try? fm.createDirectory(at: staging, withIntermediateDirectories: true)) != nil else { return false }
        for url in urls { try? fm.copyItem(at: url, to: staging.appending(path: url.lastPathComponent)) }
        try? fm.removeItem(at: dest)
        let ok = Shell.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", staging.path, dest.path]) == 0
        try? fm.removeItem(at: staging.deletingLastPathComponent())
        return ok
    }

    func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var url = dir.appending(path: "\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appending(path: "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
