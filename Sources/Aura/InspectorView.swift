import SwiftUI

struct InspectorView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WallpaperEngine.self) private var engine
    let selection: [Wallpaper]

    var body: some View {
        Group {
            if let w = selection.first, selection.count == 1 {
                Detail(wallpaper: w)
            } else if selection.count > 1 {
                multi
            } else {
                ContentUnavailableView("No Selection", systemImage: "cursorarrow.click.2",
                                       description: Text("Click a wallpaper to see details.\nDouble-click to set it."))
            }
        }
    }

    private var multi: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("\(selection.count) wallpapers").font(.title3.bold())
            Text(selection.map(\.size).reduce(0, +).fileSize).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ShareLink(items: selection.map(\.url)) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                Button { Exporter.export(selection) } label: { Label("Export Pack…", systemImage: "archivebox").frame(maxWidth: .infinity) }
                Button(role: .destructive) { library.trash(selection) } label: { Label("Move to Trash", systemImage: "trash").frame(maxWidth: .infinity) }
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
    }
}

private struct Detail: View {
    @Environment(LibraryStore.self) private var library
    @Environment(WallpaperEngine.self) private var engine
    let wallpaper: Wallpaper
    @State private var pixels: CGSize?
    @State private var palette: Palette?
    @State private var renaming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Color.clear
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay {
                        if wallpaper.kind == .live { LoopingVideo(url: wallpaper.url) } else { Thumbnail(wallpaper: wallpaper, size: 900) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(wallpaper.title).font(.title2.bold()).lineLimit(2)
                    Text(wallpaper.collection).foregroundStyle(.secondary)
                }

                Button {
                    Task { await engine.apply(wallpaper) }
                } label: {
                    Label(engine.current?.id == wallpaper.id ? "On Your Desktop" : "Set as Wallpaper",
                          systemImage: engine.current?.id == wallpaper.id ? "checkmark.circle.fill" : "desktopcomputer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                HStack(spacing: 8) {
                    iconButton(library.isFavorite(wallpaper) ? "heart.fill" : "heart", "Favorite") { library.toggleFavorite(wallpaper) }
                    ShareLink(item: wallpaper.url) { Image(systemName: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .help("Share")
                    iconButton("folder", "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url]) }
                    iconButton("pencil", "Rename") { renaming = true }
                    iconButton("trash", "Move to Trash") { library.trash([wallpaper]) }
                }
                .controlSize(.large)

                if let palette {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Palette").font(.headline)
                        HStack(spacing: 8) { ForEach(palette.colors, id: \.self) { Swatch(color: $0, size: 30) } }
                        Button {
                            ThemeManager.apply(palette)
                        } label: {
                            Label("Use as Mac Theme", systemImage: "paintpalette.fill").frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .tint(Color(nsColor: palette.accent))
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    info("Type", wallpaper.kind.title)
                    info("Resolution", pixels.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "—")
                    info("Size", wallpaper.size.fileSize)
                    info("Format", wallpaper.url.pathExtension.uppercased())
                    info("Added", wallpaper.added.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.callout)
            }
            .padding(18)
        }
        .sheet(isPresented: $renaming) { RenameSheet(wallpaper: wallpaper) }
        .task(id: wallpaper.id) {
            pixels = nil; palette = nil
            pixels = await Images.pixelSize(wallpaper)
            palette = await PaletteExtractor.extract(from: wallpaper)
        }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(maxWidth: .infinity) }.help(help)
    }

    private func info(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
