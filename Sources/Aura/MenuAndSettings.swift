import SwiftUI

struct MenuBarMenu: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WallpaperEngine.self) private var engine
    @Environment(Updater.self) private var updater
    @AppStorage(Prefs.animate) private var animate = true
    @AppStorage(Prefs.speed) private var speed = 1.0

    var body: some View {
        if let current = engine.current {
            Text(current.title)
            if let reason = engine.pauseReason { Text(reason) }
        }
        if engine.isLive && animate {
            Button(engine.userPaused ? "Resume Animation" : "Pause Animation") { engine.userPaused.toggle() }
                .keyboardShortcut("p")
        }
        Toggle("Animate Wallpapers", isOn: $animate)
        Picker("Speed", selection: $speed) {
            ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text("\($0.formatted())×").tag($0) }
        }
        .disabled(!animate)
        if engine.current != nil {
            Button("Turn Off Wallpaper") { engine.turnOff() }
        }
        Divider()
        Button("Shuffle Wallpaper") { engine.shuffle(from: library.items) }
            .keyboardShortcut("s")
        let favorites = library.items.filter(library.isFavorite)
        if !favorites.isEmpty {
            Menu("Favorites") {
                ForEach(favorites) { w in Button(w.name) { Task { await engine.apply(w) } } }
            }
        }
        Divider()
        if let release = updater.available {
            Button("Update to \(release.version)…") { Task { await updater.install(release) } }
        }
        Button("Open Aura…") { WindowOpener.show() }
            .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Aura") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
