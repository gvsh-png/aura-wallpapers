import SwiftUI
import UniformTypeIdentifiers

enum Tab: String, CaseIterable { case library = "Library", favorites = "Favorites", discover = "Discover" }

struct ContentView: View {
    @Environment(Library.self) private var library
    @AppStorage("tab") private var tab = Tab.library
    @State private var search = ""
    @State private var editing: Wallpaper?
    @State private var shuffleOptions = false

    var body: some View {
        VStack(spacing: 0) {
            header
            UpdateBanner()
            ZStack {
                switch tab {
                case .library, .favorites: LibraryGrid(items: filtered, favorites: tab == .favorites, edit: { editing = $0 })
                case .discover: WallhavenView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .background { Backdrop(accent: library.palette.color) }
        .tint(library.palette.color)
        .foregroundStyle(Matte.text)
        .font(.sora(13))
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 1.2), value: library.palette)
        .animation(.smooth, value: tab)
        .overlay(alignment: .topTrailing) {
            if shuffleOptions {
                ZStack(alignment: .topTrailing) {
                    // Click anywhere else to close.
                    Color.black.opacity(0.001).onTapGesture { shuffleOptions = false }
                    ShuffleOptions()
                        .background(RoundedRectangle(cornerRadius: 18).fill(Matte.surface))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Matte.line))
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                        .padding(.top, 52).padding(.trailing, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
                .onExitCommand { shuffleOptions = false }
            }
        }
        .animation(.smooth, value: shuffleOptions)
        .sheet(item: $editing) { Editor(wallpaper: $0) }
        .dropDestination(for: URL.self) { urls, _ in library.importFiles(urls) > 0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in library.reload() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("aura").font(.sora(17, .semibold)).tracking(1.5)
                .padding(.leading, 72) // traffic lights
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t.rawValue).font(.sora(12.5, .medium))
                            .padding(.horizontal, 14).frame(height: 28)
                            .foregroundStyle(tab == t ? Matte.text : Matte.dim)
                            .background { if tab == t { Capsule().fill(Matte.raised) } }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Capsule().fill(Matte.surface))
            .overlay(Capsule().strokeBorder(Matte.line))
            Spacer()
            if tab != .discover {
                MatteField(prompt: "Search", text: $search).frame(width: 200)
                IconButton(symbol: "plus", help: "Add your own images") { importImages() }
            }
            IconButton(symbol: "rectangle.stack", help: "Quick picker (⌃⌥W)") { Picker.shared.open() }
            IconButton(symbol: "shuffle", help: "Shuffle and auto shuffle", active: library.autoShuffle || shuffleOptions) { shuffleOptions.toggle() }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var filtered: [Wallpaper] {
        let base = tab == .favorites ? library.favoriteItems : library.items
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func importImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add"
        if panel.runModal() == .OK { library.importFiles(panel.urls) }
    }
}

/// Click a wallpaper to put it on the desktop.
struct LibraryGrid: View {
    @Environment(Library.self) private var library
    let items: [Wallpaper]
    var favorites = false
    let edit: (Wallpaper) -> Void

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: favorites ? "heart" : "photo.on.rectangle.angled").font(.system(size: 34, weight: .light)).foregroundStyle(Matte.dim)
                Text(favorites ? "No favorites yet" : "No wallpapers yet").font(.sora(17, .semibold))
                Text(favorites ? "Hover a wallpaper and tap the heart." : "Find some in Discover, or drop your own images here.").foregroundStyle(Matte.dim)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 18)], spacing: 22) {
                    ForEach(items) { w in Card(wallpaper: w, current: library.current == w.id, edit: { edit(w) }) }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .scrollIndicators(.never)
        }
    }
}

struct Card: View {
    @Environment(Library.self) private var library
    let wallpaper: Wallpaper
    let current: Bool
    let edit: () -> Void
    @State private var hover = false
    private var favorite: Bool { library.isFavorite(wallpaper) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumbnail(url: wallpaper.url)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? AnyShapeStyle(.tint) : AnyShapeStyle(Matte.line), lineWidth: current ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if hover {
                        IconButton(symbol: "slider.horizontal.3", help: "Customize", action: edit)
                            .padding(8).transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if hover || favorite {
                        IconButton(symbol: favorite ? "heart.fill" : "heart", help: favorite ? "Remove from Favorites" : "Add to Favorites",
                                   active: favorite) { library.toggleFavorite(wallpaper) }
                            .padding(8).transition(.opacity)
                    }
                }
                .scaleEffect(hover ? 1.015 : 1)
                .shadow(color: .black.opacity(hover ? 0.5 : 0), radius: 16, y: 8)
            HStack(spacing: 6) {
                if current { Circle().fill(.tint).frame(width: 6, height: 6) }
                Text(wallpaper.title).font(.sora(12.5, .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Text(wallpaper.collection).font(.sora(11)).foregroundStyle(Matte.dim).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { library.setDesktop(wallpaper) }
        .onHover { hover = $0 }
        .animation(.smooth, value: hover)
        .animation(.smooth, value: current)
        .animation(.smooth, value: favorite)
        .contextMenu {
            Button("Set as Wallpaper") { library.setDesktop(wallpaper) }
            Button(favorite ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(wallpaper) }
            Button("Customize…", action: edit)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url]) }
            Divider()
            Button("Move to Trash", role: .destructive) { library.trash(wallpaper) }
        }
    }
}

/// Shuffle now, or let Aura change the wallpaper on a schedule.
struct ShuffleOptions: View {
    @Environment(Library.self) private var library
    private let intervals = [(15, "15 min"), (30, "30 min"), (60, "1 hour"), (180, "3 hours"), (360, "6 hours"), (1440, "Daily")]

    var body: some View {
        @Bindable var library = library
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Auto shuffle").font(.sora(14, .semibold))
                Spacer()
                Toggle("", isOn: $library.autoShuffle.animation(.smooth)).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            section("Change every") {
                VStack(spacing: 6) {
                    ForEach([intervals.prefix(3), intervals.suffix(3)], id: \.first!.0) { row in
                        HStack(spacing: 6) {
                            ForEach(row, id: \.0) { m in chip(m.1, library.shuffleMinutes == m.0) { library.shuffleMinutes = m.0 } }
                        }
                    }
                }
            }
            section("Pick from") {
                HStack(spacing: 6) {
                    chip("All", !library.shuffleFavoritesOnly) { library.shuffleFavoritesOnly = false }
                    chip("Favorites", library.shuffleFavoritesOnly) { library.shuffleFavoritesOnly = true }
                }
            }
            if library.autoShuffle, let next = library.nextShuffle {
                (Text("Next change in ") + Text(next, style: .relative))
                    .font(.sora(11.5)).foregroundStyle(Matte.dim)
                Text("Aura keeps running quietly after you close its window.").font(.sora(11)).foregroundStyle(Matte.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                let pool = library.shuffleFavoritesOnly && !library.favoriteItems.isEmpty ? library.favoriteItems : library.items
                library.shuffle(pool)
            } label: { Label("Shuffle Now", systemImage: "shuffle").frame(maxWidth: .infinity) }
                .buttonStyle(.accent)
        }
        .padding(18)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .font(.sora(12))
        .foregroundStyle(Matte.text)
        .tint(library.palette.color)
        .disabled(library.items.isEmpty)
        .animation(.smooth, value: library.shuffleMinutes)
        .animation(.smooth, value: library.shuffleFavoritesOnly)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.sora(10.5, .semibold)).tracking(1.2).foregroundStyle(Matte.dim)
            content()
        }
        .opacity(library.autoShuffle || title == "Pick from" ? 1 : 0.45)
    }

    private func chip(_ title: String, _ selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.sora(11.5, .medium))
                .frame(maxWidth: .infinity).frame(height: 28)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Matte.text))
                .background(Capsule().fill(selected ? Matte.raised : Matte.surface))
                .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(Matte.line)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A thumbnail shaped like the screen and filled the way the desktop fills it, so it previews
/// exactly what you'll see. Shows at once when cached, otherwise fades in.
struct Thumbnail: View {
    let url: URL
    var corner: CGFloat = 12
    @State private var image: NSImage?

    static var screenAspect: CGFloat {
        guard let f = NSScreen.main?.frame, f.height > 0 else { return 16 / 10 }
        return f.width / f.height
    }

    init(url: URL, corner: CGFloat = 12) {
        self.url = url
        self.corner = corner
        _image = State(initialValue: Thumbs.cache.object(forKey: url as NSURL))
    }

    var body: some View {
        Matte.surface
            .aspectRatio(Self.screenAspect, contentMode: .fit)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill().transition(.opacity) } }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .task(id: url) {
                guard image == nil else { return }
                let loaded = await Thumbs.image(for: url)
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
    }
}

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(Updater.self) private var updater
    @AppStorage("autoUpdateCheck") private var autoCheck = true
    @AppStorage("keepRunning") private var keepRunning = true
    @AppStorage(SystemTheme.key) private var matchSystem = true

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Folder") {
                    HStack {
                        Text(library.folderPath).lineLimit(1).truncationMode(.middle).foregroundStyle(Matte.dim)
                        Button("Change…") { choose() }
                        if Library.root != Library.defaultRoot { Button("Reset") { library.changeFolder(to: nil) } }
                    }
                }
            }
            Section("Theme") {
                Toggle("Match the macOS accent and highlight color to the wallpaper", isOn: $matchSystem)
                    .onChange(of: matchSystem) { _, on in on ? SystemTheme.apply(library.palette) : SystemTheme.restore() }
                Text("Every app follows. macOS has eight accent colors, so Aura picks the closest. Turning this off puts your own colors back.")
                    .font(.sora(11)).foregroundStyle(Matte.dim)
            }
            Section("Quick picker") {
                Toggle("Keep running after closing the window, so ⌃⌥W works anywhere", isOn: $keepRunning)
                Text("Uses about 15 MB in the background. Off: ⌃⌥W works only while Aura is open.")
                    .font(.sora(11)).foregroundStyle(Matte.dim)
            }
            Section("Updates") {
                LabeledContent("Version", value: updater.currentVersion)
                Toggle("Check when Aura opens", isOn: $autoCheck)
                HStack {
                    switch updater.state {
                    case .idle: Text("Not checked yet").foregroundStyle(Matte.dim)
                    case .checking: Text("Checking…")
                    case .upToDate: Label("Up to date", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    case .available(let r): Text("Version \(r.version) is available").foregroundStyle(.tint)
                    case .downloading: Text("Downloading…")
                    case .installing: Text("Installing…")
                    case .failed(let why): Label(why, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Spacer()
                    if updater.busy { ProgressView().controlSize(.small) }
                    if let release = updater.available {
                        Button("Install & Relaunch") { Task { await updater.install(release) } }
                    } else {
                        Button("Check Now") { Task { await updater.check() } }.disabled(updater.busy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .font(.sora(13))
        .tint(library.palette.color)
        .preferredColorScheme(.dark)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = Library.root
        if panel.runModal() == .OK, let url = panel.url { library.changeFolder(to: url) }
    }
}
