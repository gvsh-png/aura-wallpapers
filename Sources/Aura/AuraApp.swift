import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { UserDefaults.standard.register(defaults: ["autoUpdateCheck": true, "keepRunning": true, SystemTheme.key: true]) }

    var body: some Scene {
        Window("Aura", id: "main") {
            ContentView()
                .environment(Library.shared)
                .environment(Updater.shared)
                .frame(minWidth: 820, minHeight: 540)
                .windowFullScreenBehavior(.disabled) // always a window
                .background(NoZoomButton())
        }
        .defaultSize(width: 1120, height: 740)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView()
                .environment(Library.shared)
                .environment(Updater.shared)
                .frame(width: 500)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Cleanup.runOnce()
        NSWindow.allowsAutomaticWindowTabbing = false
        // Thumbnails aren't needed while no window is open.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Thumbs.cache.removeAllObjects() }
        }
        MainActor.assumeIsolated {
            Updater.shared.checkIfDue()
            HotKey.register()
            _ = Library.shared // starts auto shuffle
        }
    }

    // macOS keeps the desktop picture on its own, so Aura can quit with its window (⌘W closes, the Dock icon reopens).
    // It stays running, small, when the ⌃⌥W picker or auto shuffle needs it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !Library.shared.autoShuffle && !UserDefaults.standard.bool(forKey: "keepRunning") }
    }
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

/// Undoes what Aura 1.x left behind: the login item, video caches and theme changes. Runs once.
enum Cleanup {
    static func runOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "cleanedUp2") else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: fm.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/com.aura.wallpapers.plist"))
        try? fm.removeItem(at: URL.cachesDirectory.appending(path: "Aura"))

        // Put back the accent, highlight and icon colors saved before 1.x changed them.
        let snapshot = d.dictionary(forKey: "originalTheme") ?? [:]
        for (key, value) in snapshot {
            switch value {
            case let s as String where s != "__absent__": Shell.run("/usr/bin/defaults", ["write", "-g", key, "-string", s])
            case let n as NSNumber: Shell.run("/usr/bin/defaults", ["write", "-g", key, "-int", String(n.intValue)])
            default: Shell.run("/usr/bin/defaults", ["delete", "-g", key])
            }
        }
        if d.string(forKey: "lastIconTint") != nil { Shell.run("/usr/bin/killall", ["Dock"]) }
        for name in ["AppleColorPreferencesChangedNotification", "AppleAquaColorVariantChanged", "AppleInterfaceThemeChangedNotification"] {
            DistributedNotificationCenter.default().postNotificationName(.init(name), object: nil, userInfo: nil, deliverImmediately: true)
        }
        // Drop every 1.x setting; only the library folder carries over.
        let folder = d.string(forKey: Library.folderKey)
        d.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.aura.wallpapers")
        d.set(folder, forKey: Library.folderKey)
        d.set(true, forKey: "cleanedUp2")
    }
}

/// Greys out the green window button, so Aura can't go full screen or zoom.
struct NoZoomButton: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    // SwiftUI can rebuild the title bar; keep the button off.
    func updateNSView(_ view: Probe, context: Context) { view.window?.standardWindowButton(.zoomButton)?.isEnabled = false }
}
