import SwiftUI
import UniformTypeIdentifiers

enum Destination: Hashable {
    case all, still, live, favorites, collection(String), studio, theme, customize
}

struct ContentView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WallpaperEngine.self) private var engine
    @State private var section: Destination? = .all
    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var showInspector = true
    @State private var importing = false

    private var tint: Color { engine.palette.map { Color(nsColor: $0.accent) } ?? .accentColor }

    var body: some View {
        NavigationSplitView {
            Sidebar(section: $section)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                Backdrop()
                detail
            }
        }
        .tint(tint)
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie, .zip], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let granted = urls.filter { $0.startAccessingSecurityScopedResource() }
                library.importFiles(urls)
                granted.forEach { $0.stopAccessingSecurityScopedResource() }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch section ?? .all {
        case .studio:
            StudioView(showLibrary: { section = .all; selection = library.newArrivals })
        case .theme:
            ThemeView()
        case .customize:
            CustomizeView()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .navigationTitle("Customize")
        default:
            LibraryView(items: filtered, title: title, selection: $selection)
                .searchable(text: $search, placement: .toolbar, prompt: "Search wallpapers")
                .inspector(isPresented: $showInspector) {
                    InspectorView(selection: selected)
                        .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
                }
                .toolbar { libraryToolbar }
        }
    }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { importing = true } label: { Label("Import", systemImage: "plus") }
                .help("Import images, videos or a .zip pack")
            if engine.isLive {
                Button { engine.userPaused.toggle() } label: {
                    Label(engine.userPaused ? "Play" : "Pause", systemImage: engine.userPaused ? "play.fill" : "pause.fill")
                }
                .help(engine.userPaused ? "Resume animation" : "Pause animation")
            }
            Button { engine.shuffle(from: filtered) } label: { Label("Shuffle", systemImage: "shuffle") }
                .help("Random wallpaper from this view")
            Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
        }
    }

    private var selected: [Wallpaper] { library.items.filter { selection.contains($0.id) } }

    private var filtered: [Wallpaper] {
        let base: [Wallpaper] = switch section ?? .all {
        case .still: library.items.filter { $0.kind == .still }
        case .live: library.items.filter { $0.kind == .live }
        case .favorites: library.items.filter(library.isFavorite)
        case .collection(let name): library.items.filter { $0.collection == name }
        default: library.items
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var title: String {
        switch section ?? .all {
        case .all: "All Wallpapers"
        case .still: "Static"
        case .live: "Animated"
        case .favorites: "Favorites"
        case .collection(let name): name
        case .studio: "Get Wallpapers"
        case .theme: "Theme"
        case .customize: "Customize"
        }
    }
}

struct Sidebar: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WallpaperEngine.self) private var engine
    @Binding var section: Destination?

    var body: some View {
        List(selection: $section) {
            Section("Library") {
                row("All Wallpapers", "square.grid.2x2", .all, library.items.count)
                row("Static", "photo", .still, library.items.filter { $0.kind == .still }.count)
                row("Animated", "play.rectangle", .live, library.items.filter { $0.kind == .live }.count)
                row("Favorites", "heart", .favorites, library.favorites.count)
            }
            Section("Create") {
                Label("Get Wallpapers", systemImage: "wand.and.stars").tag(Destination.studio)
                Label("Theme", systemImage: "paintpalette").tag(Destination.theme)
                Label("Customize", systemImage: "slider.horizontal.3").tag(Destination.customize)
            }
            Section("Collections") {
                ForEach(library.collections, id: \.name) { c in
                    row(c.name, "rectangle.stack", .collection(c.name), c.count)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { NowPlaying().padding(10) }
    }

    private func row(_ title: String, _ symbol: String, _ tag: Destination, _ count: Int) -> some View {
        Label(title, systemImage: symbol).badge(count).tag(tag)
    }
}

/// Mini card at the bottom of the sidebar showing what is on the desktop.
struct NowPlaying: View {
    @Environment(WallpaperEngine.self) private var engine

    var body: some View {
        if let current = engine.current {
            HStack(spacing: 10) {
                Thumbnail(wallpaper: current, size: 160)
                    .frame(width: 54, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(current.kind == .live ? (engine.pauseReason ?? "Live") : "On desktop")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if engine.isLive {
                    Button { engine.userPaused.toggle() } label: {
                        Image(systemName: engine.userPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
