import AppKit
import AVFoundation
import IOKit.ps
import Observation

/// Sets the desktop picture and runs desktop-level windows behind the icons for video and dimming.
@MainActor @Observable
final class WallpaperEngine {
    static let shared = WallpaperEngine()

    private(set) var current: Wallpaper?
    private(set) var palette: Palette?
    private(set) var isPlaying = false
    /// True while an optimized copy of the current animated wallpaper is being made.
    private(set) var optimizing = false
    var userPaused = false { didSet { refreshPlayback() } }

    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var players: [AVQueuePlayer] = []
    @ObservationIgnored private var loopers: [AVPlayerLooper] = []
    @ObservationIgnored private var playerLayers: [AVPlayerLayer] = []
    @ObservationIgnored private var dimLayers: [CALayer] = []
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var layoutKey = ""
    @ObservationIgnored private var stillURL: URL?
    @ObservationIgnored private var appliedScaling: Scaling?
    @ObservationIgnored private var timer: Timer?
    /// What the player actually opens: an optimized copy, or nil for the original file.
    @ObservationIgnored private var playURL: URL?
    @ObservationIgnored private var playbackKey = ""
    @ObservationIgnored private var lastSettings: LiveSettings?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild(force: true) }
        }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPlayback() }
        }
        // ponytail: 20s poll for battery state and rotation; use IOPSNotificationCreateRunLoopSource if that lag matters
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var isLive: Bool { current?.kind == .live }
    var animates: Bool { isLive && Prefs.bool(Prefs.animate) }

    /// Why an animated wallpaper is not moving right now, for the UI.
    var pauseReason: String? {
        guard isLive else { return nil }
        if !Prefs.bool(Prefs.animate) { return "Animation off" }
        if userPaused { return "Paused" }
        if Prefs.bool(Prefs.pauseInLowPower) && ProcessInfo.processInfo.isLowPowerModeEnabled { return "Paused in Low Power Mode" }
        if Prefs.bool(Prefs.pauseOnBattery) && Self.onBattery { return "Paused on battery" }
        return isPlaying ? nil : "Paused while covered"
    }

    func apply(_ w: Wallpaper) async {
        rememberOriginalDesktop()
        current = w
        UserDefaults.standard.set(w.url.path, forKey: "currentWallpaper")
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastRotation")
        preparePlayback(w)
        rebuild()
        // Animated wallpapers also get their poster frame as the real desktop picture,
        // so Mission Control, new Spaces and the "animation off" state all match.
        let still = await Images.stillURL(for: w)
        guard current?.id == w.id else { return }
        stillURL = still
        setDesktopPicture()
        let p = await PaletteExtractor.extract(from: w)
        guard current?.id == w.id else { return }
        palette = p
        if let p, Prefs.bool(Prefs.autoTheme) { ThemeManager.apply(p) }
    }

    /// Resumes the last wallpaper after launch without touching the system theme.
    func restore() {
        guard let path = UserDefaults.standard.string(forKey: "currentWallpaper"),
              let w = Wallpaper(url: URL(fileURLWithPath: path)) else { return }
        current = w
        appliedScaling = Scaling.current
        preparePlayback(w)
        rebuild()
        Task {
            stillURL = await Images.stillURL(for: w)
            let p = await PaletteExtractor.extract(from: w)
            if current?.id == w.id { palette = p }
        }
    }

    /// Stops Aura's wallpaper and puts back the desktop picture you had before Aura changed it.
    func turnOff() {
        current = nil
        palette = nil
        stillURL = nil
        UserDefaults.standard.removeObject(forKey: "currentWallpaper")
        rebuild()
        restoreOriginalDesktop()
    }

    var hasOriginalDesktop: Bool { UserDefaults.standard.dictionary(forKey: Self.originalDesktopKey) != nil }

    // MARK: - The user's own wallpaper

    private static let originalDesktopKey = "originalDesktop"

    private static func screenID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    /// Saves each screen's desktop picture the first time Aura replaces it.
    private func rememberOriginalDesktop() {
        guard !hasOriginalDesktop else { return }
        var saved: [String: String] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) { saved[Self.screenID(screen)] = url.path }
        }
        if !saved.isEmpty { UserDefaults.standard.set(saved, forKey: Self.originalDesktopKey) }
    }

    private func restoreOriginalDesktop() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.originalDesktopKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let path = saved[Self.screenID(screen)] ?? saved.values.first,
                  FileManager.default.fileExists(atPath: path) else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        UserDefaults.standard.removeObject(forKey: Self.originalDesktopKey)
    }

    func adoptRenamed(_ w: Wallpaper) {
        current = w
        UserDefaults.standard.set(w.url.path, forKey: "currentWallpaper")
    }

    func shuffle(from items: [Wallpaper]) {
        guard let next = items.filter({ $0.id != current?.id }).randomElement() else { return }
        Task { await apply(next) }
    }

    func refreshPlayback() {
        let blocked = userPaused
            || (Prefs.bool(Prefs.pauseOnBattery) && Self.onBattery)
            || (Prefs.bool(Prefs.pauseInLowPower) && ProcessInfo.processInfo.isLowPowerModeEnabled)
        let pauseWhenCovered = Prefs.bool(Prefs.pauseWhenCovered)
        var playing = false
        for (window, player) in zip(windows, players) {
            if !blocked && (!pauseWhenCovered || window.occlusionState.contains(.visible)) {
                player.play()
                playing = true
            } else {
                player.pause()
            }
        }
        if isPlaying != playing { isPlaying = playing }
    }

    /// Re-picks the playback file after the quality for `w` changed.
    func qualityChanged(for w: Wallpaper) {
        guard let current, current.id == w.id else { return }
        preparePlayback(current)
    }

    /// Uses a cached optimized copy right away if there is one, otherwise plays the original
    /// and swaps to the optimized copy once it's ready.
    private func preparePlayback(_ w: Wallpaper) {
        guard w.kind == .live else { playURL = nil; playbackKey = ""; optimizing = false; return }
        let quality = VideoOptimizer.quality(for: w)
        let cap = Prefs.bool(Prefs.capFrameRate)
        let key = "\(w.id)|\(quality.rawValue)|\(cap)"
        guard key != playbackKey else { return }
        playbackKey = key
        if let hit = VideoOptimizer.cached(w.url, quality: quality, cap30: cap) {
            playURL = hit
            optimizing = false
            rebuild(force: true)
            return
        }
        playURL = nil
        optimizing = true
        rebuild(force: true)
        Task {
            let url = await VideoOptimizer.playable(w.url, quality: quality, cap30: cap)
            guard playbackKey == key else { return }
            optimizing = false
            if url != w.url {
                playURL = url
                rebuild(force: true)
            }
        }
    }

    // MARK: - Settings

    /// Everything that changes how the desktop windows play. Other defaults writes are ignored.
    private struct LiveSettings: Equatable {
        let animate, sound, pauseCovered, pauseBattery, pauseLowPower, cap: Bool
        let speed, volume, dim: Double
        let scaling, quality: String

        static var now: LiveSettings {
            LiveSettings(animate: Prefs.bool(Prefs.animate), sound: Prefs.bool(Prefs.sound),
                         pauseCovered: Prefs.bool(Prefs.pauseWhenCovered), pauseBattery: Prefs.bool(Prefs.pauseOnBattery),
                         pauseLowPower: Prefs.bool(Prefs.pauseInLowPower), cap: Prefs.bool(Prefs.capFrameRate),
                         speed: Prefs.double(Prefs.speed), volume: Prefs.double(Prefs.volume), dim: Prefs.double(Prefs.dim),
                         scaling: Prefs.string(Prefs.scaling),
                         quality: Prefs.string(Prefs.videoQuality) + "\(UserDefaults.standard.dictionary(forKey: "videoQualityOverrides") ?? [:])")
        }
    }

    private func settingsChanged() {
        let settings = LiveSettings.now
        guard settings != lastSettings else { return }
        lastSettings = settings
        if let current { preparePlayback(current) }
        rebuild()
        let speed = Float(Prefs.double(Prefs.speed))
        let sound = Prefs.bool(Prefs.sound)
        let volume = Float(Prefs.double(Prefs.volume))
        for player in players {
            player.defaultRate = speed
            if player.rate != 0 { player.rate = speed }
            player.isMuted = !sound
            player.volume = volume
        }
        let gravity = Self.gravity(Scaling.current)
        for layer in playerLayers where layer.videoGravity != gravity { layer.videoGravity = gravity }
        let dim = Float(Prefs.double(Prefs.dim))
        for layer in dimLayers where layer.opacity != dim { layer.opacity = dim }
        if appliedScaling != Scaling.current { setDesktopPicture() }
        refreshPlayback()
    }

    private func tick() {
        refreshPlayback()
        let minutes = Prefs.int(Prefs.rotateMinutes)
        guard minutes > 0 else { return }
        let last = UserDefaults.standard.double(forKey: "lastRotation")
        guard Date.now.timeIntervalSince1970 - last >= Double(minutes * 60) else { return }
        let library = LibraryStore.shared
        let pool: [Wallpaper] = switch RotateSource.current {
        case .all: library.items
        case .favorites: library.items.filter(library.isFavorite)
        case .still: library.items.filter { $0.kind == .still }
        case .live: library.items.filter { $0.kind == .live }
        }
        shuffle(from: pool)
    }

    private func setDesktopPicture() {
        let scaling = Scaling.current
        appliedScaling = scaling
        guard let stillURL else { return }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = switch scaling {
        case .fill: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true]
        case .fit: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: false, .fillColor: NSColor.black]
        case .stretch: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue]
        }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(stillURL, for: screen, options: options)
        }
    }

    // MARK: - Desktop windows

    /// One borderless window per screen at desktop level: video (if animating) plus a dim layer (if dimming).
    private func rebuild(force: Bool = false) {
        let wantsVideo = animates
        let wantsDim = current != nil && Prefs.double(Prefs.dim) > 0.001
        let key = "\(current?.id ?? "")|\(wantsVideo)|\(wantsDim)"
        guard force || key != layoutKey else { return }
        layoutKey = key

        tokens.forEach(NotificationCenter.default.removeObserver)
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        tokens = []; windows = []; players = []; loopers = []; playerLayers = []; dimLayers = []
        guard let w = current, wantsVideo || wantsDim else {
            refreshPlayback()
            return
        }

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.isOpaque = wantsVideo
            window.backgroundColor = wantsVideo ? .black : .clear
            window.setFrame(screen.frame, display: false)

            let bounds = CGRect(origin: .zero, size: screen.frame.size)
            let root = CALayer()
            root.frame = bounds
            window.contentView?.layer = root
            window.contentView?.wantsLayer = true

            if wantsVideo {
                let player = AVQueuePlayer()
                player.preventsDisplaySleepDuringVideoPlayback = false
                player.defaultRate = Float(Prefs.double(Prefs.speed))
                player.isMuted = !Prefs.bool(Prefs.sound)
                player.volume = Float(Prefs.double(Prefs.volume))
                loopers.append(AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: playURL ?? w.url)))
                let layer = AVPlayerLayer(player: player)
                layer.frame = bounds
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.videoGravity = Self.gravity(Scaling.current)
                root.addSublayer(layer)
                playerLayers.append(layer)
                players.append(player)
                tokens.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshPlayback() }
                })
            }

            let dim = CALayer()
            dim.frame = bounds
            dim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            dim.backgroundColor = NSColor.black.cgColor
            dim.opacity = Float(Prefs.double(Prefs.dim))
            root.addSublayer(dim)
            dimLayers.append(dim)

            window.orderBack(nil)
            windows.append(window)
        }
        refreshPlayback()
    }

    private static func gravity(_ s: Scaling) -> AVLayerVideoGravity {
        switch s {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        case .stretch: .resize
        }
    }

    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
