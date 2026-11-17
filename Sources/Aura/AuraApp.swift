import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { UserDefaults.standard.register(defaults: ["autoUpdateCheck": true]) }

    var body: some Scene {
        Window("Aura", id: "main") {
            ContentView()
                .environment(Library.shared)
                .environment(Updater.shared)
                .frame(minWidth: 820, minHeight: 540)
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
        // Always a window: no full screen, the green button only zooms.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
        }
        MainActor.assumeIsolated { Updater.shared.checkIfDue() }
    }

    // macOS keeps the desktop picture on its own, so Aura quits with its window: ⌘W closes, the Dock icon reopens.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
