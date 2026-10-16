import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WallpaperEngine.self) private var engine
    let items: [Wallpaper]
    let title: String
    @Binding var selection: Set<String>
    @State private var renaming: Wallpaper?

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !library.newArrivals.isEmpty { arrivals }
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Drop images, videos or a .zip pack here, use Get Wallpapers, or start with the starter pack.")
                    } actions: {
                        Button(library.installingStarter ? "Downloading…" : "Download Starter Pack") { library.installStarterPack() }
                            .buttonStyle(.borderedProminent)
                            .disabled(library.installingStarter)
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(items) { w in
                            WallpaperCard(wallpaper: w,
                                          selected: selection.contains(w.id),
                                          active: engine.current?.id == w.id,
                                          isNew: library.newArrivals.contains(w.id),
                                          favorite: library.isFavorite(w))
                                .onTapGesture(count: 2) { Task { await engine.apply(w) } }
                                .simultaneousGesture(TapGesture().onEnded { select(w) })
                                .contextMenu { menu(for: w) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(title)
        .dropDestination(for: URL.self) { urls, _ in library.importFiles(urls) > 0 }
        .sheet(item: $renaming) { RenameSheet(wallpaper: $0) }
        .onKeyPress(.return) {
            guard let w = items.first(where: { selection.contains($0.id) }) else { return .ignored }
            Task { await engine.apply(w) }
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded))
            Text("\(items.count)").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var arrivals: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(library.newArrivals.count) new wallpaper\(library.newArrivals.count == 1 ? "" : "s") arrived").font(.headline)
                Text("Marked NEW below. Double-click one to set it.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select New") { selection = library.newArrivals }
            Button("Dismiss") { withAnimation { library.newArrivals = [] } }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func select(_ w: Wallpaper) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) || mods.contains(.shift) {
            if selection.remove(w.id) == nil { selection.insert(w.id) }
        } else {
            selection = [w.id]
        }
    }

    @ViewBuilder private func menu(for w: Wallpaper) -> some View {
        let targets = selection.contains(w.id) ? items.filter { selection.contains($0.id) } : [w]
        Button("Set as Wallpaper") { Task { await engine.apply(w) } }
        Button(library.isFavorite(w) ? "Remove from Favorites" : "Add to Favorites") { library.toggleFavorite(w) }
        Divider()
        ShareLink(items: targets.map(\.url)) { Text("Share…") }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(targets.map { $0.url as NSURL })
        }
        Button("Export Pack…") { Exporter.export(targets) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url)) }
        Divider()
        Button("Rename…") { renaming = w }
        Button("Move to Trash", role: .destructive) {
            selection.subtract(targets.map(\.id))
            library.trash(targets)
        }
    }
}

struct WallpaperCard: View {
    let wallpaper: Wallpaper
    let selected: Bool
    let active: Bool
    let isNew: Bool
    let favorite: Bool
    @State private var hovering = false

    var body: some View {
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                ZStack {
                    Thumbnail(wallpaper: wallpaper)
                    if hovering && wallpaper.kind == .live {
                        LoopingVideo(url: wallpaper.url).transition(.opacity)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 70)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(wallpaper.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(wallpaper.collection).font(.caption).opacity(0.75).lineLimit(1)
                }
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .padding(12)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    if active { Badge(text: "On Desktop", symbol: "checkmark.circle.fill", tint: .accentColor) }
                    if wallpaper.kind == .live { Badge(text: "Live", symbol: "play.fill") }
                    if isNew { Badge(text: "New", symbol: "sparkles", tint: .pink) }
                }
                .padding(10)
            }
            .overlay(alignment: .topTrailing) {
                if favorite {
                    Image(systemName: "heart.fill").foregroundStyle(.pink).shadow(radius: 3).padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .cardOutline(selected: selected, active: active)
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.18), radius: hovering ? 16 : 8, y: hovering ? 8 : 4)
            .scaleEffect(hovering ? 1.025 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct RenameSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let wallpaper: Wallpaper
    @State private var collection = ""
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Wallpaper").font(.title2.bold())
            Form {
                TextField("Collection", text: $collection)
                TextField("Title", text: $title)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") { library.rename(wallpaper, collection: collection, title: title); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            collection = wallpaper.collection == "Unsorted" ? "" : wallpaper.collection
            title = wallpaper.title
        }
    }
}

enum Exporter {
    @MainActor static func export(_ ws: [Wallpaper]) {
        guard !ws.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let chars = Set(ws.map(\.collection))
        panel.nameFieldStringValue = "\(chars.count == 1 ? chars.first! : "Aura") Wallpapers.zip"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let urls = ws.map(\.url)
        Task.detached(priority: .userInitiated) {
            if LibraryStore.exportPack(urls, to: dest) {
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
            }
        }
    }
}
