import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    static let launchedInBackground = CommandLine.arguments.contains("--background")
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    init() { Prefs.register() }

    var body: some Scene {
        Window("Aura", id: "main") {
            ContentView()
                .environment(LibraryStore.shared)
                .environment(WallpaperEngine.shared)
                .environment(AgentStudio.shared)
                .environment(Updater.shared)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(Self.launchedInBackground ? .suppressed : .presented)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarMenu()
                .environment(LibraryStore.shared)
                .environment(WallpaperEngine.shared)
                .environment(Updater.shared)
        } label: {
            MenuBarLabel()
        }

        Settings {
            CustomizeView()
                .environment(LibraryStore.shared)
                .environment(WallpaperEngine.shared)
                .environment(Updater.shared)
                .font(.aura(.body))
                .frame(width: 520, height: 640)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AuraApp.launchedInBackground { NSApp.setActivationPolicy(.accessory) }
        MainActor.assumeIsolated {
            let library = LibraryStore.shared
            WallpaperEngine.shared.restore()
            // 1.1.4: icon tinting became opt-in. Undo tinting left over from older versions.
            if UserDefaults.standard.string(forKey: "lastIconTint") != nil, !Prefs.bool(Prefs.tintIcons) {
                ThemeManager.resetIcons()
            }
            // First launch with an empty library: fetch the starter pack.
            if !UserDefaults.standard.bool(forKey: "starterOffered") {
                UserDefaults.standard.set(true, forKey: "starterOffered")
                if library.items.isEmpty { library.installStarterPack() }
            }
            // `Aura --update` checks and installs right away (scripts, support).
            if CommandLine.arguments.contains("--update") {
                Task {
                    await Updater.shared.check()
                    if let release = Updater.shared.available { await Updater.shared.install(release) }
                }
            } else {
                Updater.shared.checkIfDue()
            }
        }
        LoginItem.refresh()
    }

    // Clicking the app in Finder or the Dock while it runs in the background brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { WindowOpener.show() }
        return false
    }

    // Keep playing the wallpaper after the window closes; the menu bar icon stays.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Holds SwiftUI's openWindow action so AppKit callbacks can show the main window.
@MainActor enum WindowOpener {
    static var action: OpenWindowAction?

    static func show() {
        NSApp.setActivationPolicy(.regular)
        action?(id: "main")
        NSApp.activate()
    }
}

/// The menu bar icon. It exists for the app's whole life, so it is where openWindow gets captured.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "sparkles.rectangle.stack")
            .onAppear { WindowOpener.action = openWindow }
    }
}
