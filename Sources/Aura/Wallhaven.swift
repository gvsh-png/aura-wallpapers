import SwiftUI

/// One search hit from the wallhaven.cc API.
struct WallhavenResult: Decodable, Identifiable, Hashable {
    let id: String
    let url: URL        // page on wallhaven.cc
    let path: URL       // full-size file
    let resolution: String
    let fileSize: Int64
    let thumbs: [String: URL]
}

struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Wallhaven {
    private struct Page: Decodable {
        struct Meta: Decodable { let lastPage: Int }
        let data: [WallhavenResult]
        let meta: Meta
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    static let sortings = [("relevance", "Relevance"), ("toplist", "Top"), ("favorites", "Favorites"), ("views", "Views"), ("date_added", "Newest")]
    static let sizes = [("", "Any"), ("1920x1080", "1080p"), ("2560x1440", "1440p"), ("3840x2160", "4K")]

    /// SFW and landscape only. No API key needed.
    static func search(_ query: String, sorting: String, atLeast: String, page: Int) async throws -> (items: [WallhavenResult], lastPage: Int) {
        var c = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        c.queryItems = [
            .init(name: "q", value: query),
            .init(name: "categories", value: "111"),
            .init(name: "purity", value: "100"),
            .init(name: "ratios", value: "landscape"),
            // relevance needs a query; browse the toplist otherwise
            .init(name: "sorting", value: query.isEmpty && sorting == "relevance" ? "toplist" : sorting),
            .init(name: "page", value: String(page)),
        ]
        if !atLeast.isEmpty { c.queryItems!.append(.init(name: "atleast", value: atLeast)) }
        let (data, response) = try await URLSession.shared.data(for: request(c.url!))
        try check(response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let page = try decoder.decode(Page.self, from: data)
        return (page.data, page.meta.lastPage)
    }

    /// Streams the full-size file to disk, then moves it into the library as "<collection> - Wallhaven <id>.<ext>".
    @MainActor
    static func download(_ r: WallhavenResult, collection: String) async throws {
        let (tmp, response) = try await URLSession.shared.download(for: request(r.path, timeout: 120))
        try check(response)
        let library = Library.shared
        let ext = r.path.pathExtension.isEmpty ? "jpg" : r.path.pathExtension.lowercased()
        try FileManager.default.moveItem(at: tmp, to: library.uniqueURL(base: "\(collection) - Wallhaven \(r.id)", ext: ext))
        library.reload()
    }

    private static func request(_ url: URL, timeout: TimeInterval = 30) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    private static func check(_ response: URLResponse) throws {
        switch (response as? HTTPURLResponse)?.statusCode ?? 200 {
        case 200..<300: return
        case 429: throw Failure(message: "Wallhaven is rate limiting. Wait a minute and try again.")
        case let s: throw Failure(message: "Wallhaven said \(s)")
        }
    }
}

/// Search wallhaven.cc, pick the ones you like, download them into the library.
struct WallhavenView: View {
    enum Job { case running, done, failed(String) }

    @Environment(Library.self) private var library
    @AppStorage("wallhavenQuery") private var query = ""
    @AppStorage("wallhavenSorting") private var sorting = "relevance"
    @AppStorage("wallhavenAtLeast") private var atLeast = "3840x2160"
    @State private var results: [WallhavenResult] = []
    @State private var searched = ""
    @State private var page = 0
    @State private var lastPage = 1
    @State private var loading = false
    @State private var error: String?
    @State private var picked: Set<String> = []
    @State private var jobs: [String: Job] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    MatteField(prompt: "Search a character, anime, game, place…", text: $query) { search(reset: true) }
                    Button("Search") { search(reset: true) }.buttonStyle(.accent).disabled(loading)
                }
                HStack(spacing: 10) {
                    menu(Wallhaven.sortings, $sorting)
                    menu(Wallhaven.sizes, $atLeast)
                    Spacer()
                    Text("from wallhaven.cc · SFW · landscape").font(.sora(11)).foregroundStyle(Matte.dim)
                }
                .onChange(of: sorting) { if !results.isEmpty { search(reset: true) } }
                .onChange(of: atLeast) { if !results.isEmpty { search(reset: true) } }

                if let error { Text(error).foregroundStyle(.orange) }
                if !loading && results.isEmpty && !searched.isEmpty && error == nil {
                    Text("Nothing found for “\(searched)”.").foregroundStyle(Matte.dim)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 18)], spacing: 18) {
                    let owned = owned
                    ForEach(results) { card($0, have: owned.contains($0.id)) }
                }

                HStack {
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                    else if page < lastPage && !results.isEmpty { Button("Load More") { search(reset: false) }.buttonStyle(.matte) }
                    Spacer()
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .bottom) { if !picked.isEmpty { actionBar } }
        .animation(.smooth, value: picked.isEmpty)
    }

    /// Wallhaven ids already in the library, read from "… - Wallhaven <id>" file names.
    private var owned: Set<String> {
        Set(library.items.compactMap { $0.name.components(separatedBy: "Wallhaven ").dropFirst().last })
    }

    private var collection: String {
        let name = Library.sanitize(searched)
        return name.isEmpty ? "Wallhaven" : name.capitalized
    }

    private func card(_ r: WallhavenResult, have: Bool) -> some View {
        let selected = picked.contains(r.id)
        return Button {
            guard !have, jobs[r.id] == nil else { return }
            if picked.remove(r.id) == nil { picked.insert(r.id) }
        } label: {
            Matte.surface
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    // "small" thumbs are 300×200: plenty for a card and light on memory
                    AsyncImage(url: r.thumbs["small"]) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("\(r.resolution) · \(ByteCountFormatter.string(fromByteCount: r.fileSize, countStyle: .file))")
                        .font(.sora(10.5, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) { status(r, selected: selected, have: have).padding(6) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Matte.line), lineWidth: selected ? 2 : 1))
                .animation(.smooth, value: selected)
                .opacity(have ? 0.5 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(have ? "Already in your library" : "Click to select")
        .contextMenu {
            Button("Open on Wallhaven") { NSWorkspace.shared.open(r.url) }
            Button("Download Now") { download([r]) }.disabled(have)
        }
    }

    @ViewBuilder private func status(_ r: WallhavenResult, selected: Bool, have: Bool) -> some View {
        Group {
            switch jobs[r.id] {
            case .running: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let why): Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(why)
            case nil:
                if have { Image(systemName: "tray.full.fill").foregroundStyle(.white) }
                else { Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white)) }
            }
        }
        .font(.system(size: 15))
        .frame(width: 28, height: 28)
        .background(.black.opacity(0.45), in: Circle())
    }

    private var actionBar: some View {
        HStack {
            Text("\(picked.count) selected").font(.sora(12.5, .semibold))
            Text("→ \(collection)").foregroundStyle(Matte.dim)
            Spacer()
            Button("Clear") { picked = [] }.buttonStyle(.matte)
            Button("Download \(picked.count)") { download(results.filter { picked.contains($0.id) }) }.buttonStyle(.accent)
        }
        .padding(10).padding(.leading, 6)
        .background(Capsule().fill(Matte.raised))
        .overlay(Capsule().strokeBorder(Matte.line))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Matte pill that opens a menu of options.
    private func menu(_ options: [(String, String)], _ value: Binding<String>) -> some View {
        Menu {
            ForEach(options, id: \.0) { o in Button(o.1) { value.wrappedValue = o.0 } }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.0 == value.wrappedValue }?.1 ?? "").font(.sora(12, .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Matte.dim)
            }
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(Matte.surface))
            .overlay(Capsule().strokeBorder(Matte.line))
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
    }

    private func download(_ items: [WallhavenResult]) {
        let collection = collection
        for r in items {
            picked.remove(r.id)
            jobs[r.id] = .running
            Task {
                do {
                    try await Wallhaven.download(r, collection: collection)
                    jobs[r.id] = .done
                } catch {
                    jobs[r.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func search(reset: Bool) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = reset ? 1 : page + 1
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                let found = try await Wallhaven.search(q, sorting: sorting, atLeast: atLeast, page: next)
                if reset { results = []; picked = []; searched = q }
                let seen = Set(results.map(\.id))
                results += found.items.filter { !seen.contains($0.id) }
                page = next
                lastPage = found.lastPage
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
