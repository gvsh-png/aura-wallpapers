import SwiftUI
import UniformTypeIdentifiers

enum Tab: String, CaseIterable { case library = "Library", discover = "Discover" }

struct ContentView: View {
    @Environment(Library.self) private var library
    @AppStorage("tab") private var tab = Tab.library
    @State private var search = ""
    @State private var editing: Wallpaper?

    var body: some View {
        VStack(spacing: 0) {
            header
            UpdateBanner()
            ZStack {
                switch tab {
                case .library: LibraryGrid(items: filtered, edit: { editing = $0 })
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
            if tab == .library {
                MatteField(prompt: "Search", text: $search).frame(width: 200)
                IconButton(symbol: "plus", help: "Add your own images") { importImages() }
                IconButton(symbol: "shuffle", help: "Random wallpaper") { library.shuffle(filtered) }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var filtered: [Wallpaper] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? library.items : library.items.filter { $0.name.localizedCaseInsensitiveContains(q) }
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
    let edit: (Wallpaper) -> Void

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34, weight: .light)).foregroundStyle(Matte.dim)
                Text("No wallpapers yet").font(.sora(17, .semibold))
                Text("Find some in Discover, or drop your own images here.").foregroundStyle(Matte.dim)
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
        .contextMenu {
            Button("Set as Wallpaper") { library.setDesktop(wallpaper) }
            Button("Customize…", action: edit)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([wallpaper.url]) }
            Divider()
            Button("Move to Trash", role: .destructive) { library.trash(wallpaper) }
        }
    }
}

/// A 16:10 thumbnail from a local file.
struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Matte.surface
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill().transition(.opacity) } }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: url) {
                let loaded = await Thumbs.image(for: url)
                withAnimation(.easeOut(duration: 0.3)) { image = loaded }
            }
    }
}

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(Updater.self) private var updater
    @AppStorage("autoUpdateCheck") private var autoCheck = true

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
