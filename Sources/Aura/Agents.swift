import AppKit
import Observation
import UniformTypeIdentifiers

enum AgentTarget: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case cursor = "Cursor"
    case codex = "Codex"
    case geminiCLI = "Gemini CLI"
    case chatGPT = "ChatGPT"
    case claude = "Claude.ai"
    case gemini = "Gemini"

    var id: String { rawValue }

    /// Agents with a terminal download straight into the library; chat agents reply with links.
    var hasShell: Bool { [.claudeCode, .cursor, .codex, .geminiCLI].contains(self) }

    /// How to start this agent as an Agent Client Protocol server, when it supports one.
    var acpCommand: (String, [String])? {
        switch self {
        case .claudeCode: ("npx", ["-y", "@agentclientprotocol/claude-agent-acp"])
        case .codex: ("npx", ["-y", "@agentclientprotocol/codex-acp"])
        case .geminiCLI: ("gemini", ["--experimental-acp"])
        default: nil
        }
    }

    var supportsACP: Bool { acpCommand != nil }

    var symbol: String {
        switch self {
        case .claudeCode: "terminal"
        case .cursor: "cursorarrow.rays"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: "sparkles"
        case .chatGPT: "bubble.left.and.text.bubble.right"
        case .claude: "sparkle"
        case .gemini: "diamond"
        }
    }

    var howTo: String {
        if supportsACP {
            return "Click Run Now. Aura sends the prompt straight to \(rawValue) and shows its progress here. Approve its downloads as they come up. You can also copy the prompt instead."
        }
        return hasShell
            ? "Paste into \(rawValue). It downloads straight into your library, and Aura shows new wallpapers within seconds."
            : "Paste into \(rawValue) with web search on. Copy its whole reply, then click Paste Reply here."
    }

    /// Where "Copy & Open" goes.
    var destination: URL? {
        switch self {
        case .claudeCode, .codex, .geminiCLI: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        case .cursor: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92")
        case .chatGPT: URL(string: "https://chatgpt.com")
        case .claude: URL(string: "https://claude.ai/new")
        case .gemini: URL(string: "https://gemini.google.com/app")
        }
    }
}

enum PromptBuilder {
    static func make(subject: String, hints: String, kind: WallpaperKind, count: Int, agent: AgentTarget) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        let what = trimmed.isEmpty ? "<SUBJECT>" : trimmed
        let screen = NSScreen.main.map { "\(Int($0.frame.width * $0.backingScaleFactor))×\(Int($0.frame.height * $0.backingScaleFactor))" } ?? "2560×1600"
        let type = kind == .live ? "animated (looping video)" : "static"
        let wishes = hints.trimmingCharacters(in: .whitespaces)
        let extra = wishes.isEmpty ? "" : "\nExtra wishes: \(wishes)"
        let floor = MinQuality.current
        let minimum = floor == .any ? "the highest resolution available" : "at least \(floor.size) (\(floor.title)); smaller files are rejected automatically"
        let format = kind == .live
            ? "- MP4 or MOV (H.264 or HEVC), \(minimum). Always pick the 4K/2160p download option when a site offers several. Loops cleanly, under 300 MB. Sound does not matter.\n- Good sources: pexels.com/videos, mixkit.co, pixabay.com/videos, coverr.co."
            : "- JPG or PNG, landscape, \(minimum). My screen is \(screen); 4K, 5K or larger originals are best. Always take the original/full-size file, never a preview.\n- Good sources: unsplash.com, pexels.com, wallhaven.cc (SFW only), images.nasa.gov."

        let header = """
        I use Aura, a Mac wallpaper app. Find \(count) high-quality \(type) desktop wallpapers matching: \(what).\(extra)

        Requirements
        \(format)
        - Each one clearly fits "\(what)" and works as a desktop background (calm areas for icons, no text overlays).
        - Varied scenes and creators. No NSFW, no watermarks, no tiny upscales, nothing behind a login or paywall.
        - Prefer free-license sources. Note the creator or source page for each.

        """

        let folder = kind == .live ? "~/Pictures/Wallpapers/Live" : "~/Pictures/Wallpapers/Static"
        let deliver = agent.hasShell
            ? """
            Deliver
            1. Download each file into \(folder)/ with a browser User-Agent and the page as Referer:
               curl -L -A "Mozilla/5.0 (Macintosh)" -e "<page url>" -o "\(folder)/\(what) - <short title>.<ext>" "<direct file url>"
            2. Name every file "\(what) - <short title>.<ext>". Aura groups wallpapers into collections by the part before " - ".
            3. Run `file` on each download. Delete anything that is HTML, an error page, or under 100 KB, then find a replacement.
            4. List the folder first. Skip anything already there, and don't save the same wallpaper twice (even at another size). Never touch existing files.
            5. Finish with a table: file, resolution, source page.
            Full rules live in ~/Pictures/Wallpapers/AGENTS.md.
            """
            : """
            Deliver
            Search the web, then reply with ONE code block tagged aura holding only direct file links, one per line:
            ```aura
            https://example.com/full-size-file.\(kind == .live ? "mp4" : "jpg")
            ```
            Each link must be a different wallpaper. Direct links only: each must open the actual \(kind == .live ? ".mp4/.mov" : ".jpg/.png") file, not a gallery or post page. Open each link to check it before you answer. Give \(count + 2) links in case some fail. After the block, list the source page and creator for each.
            """
        return header + deliver
    }
}

/// Instruction files so any coding agent opened in the library folder knows the rules.
enum AgentDocs {
    static let header = "# Aura wallpaper library"
    static let agentsMD = """
    \(header)

    This folder is the library for **Aura**, a native macOS wallpaper app. Aura checks it every 2 seconds and shows new files right away.

    ## Layout
    - `Static/` still wallpapers: `.jpg` `.jpeg` `.png` `.heic` `.webp`
    - `Live/` animated wallpapers: `.mp4` `.mov` `.m4v` (looped; the user controls speed, sound and pausing)

    ## Naming
    `<Collection> - <short title>.<ext>`, for example `Mountains - Alpine lake at dawn.jpg`.
    Aura groups wallpapers into collections by the text before ` - `. Keep titles short and readable.

    ## Quality bar
    - Landscape, 4K (3840×2160) or larger for both static and animated unless the user asks otherwise. Always take the original/2160p download. Aura moves files below the user's quality setting to the Trash.
    - Animated: clean loop, under 300 MB.
    - Fits the request and works as a desktop background: calm areas for icons, no text overlays.
    - No NSFW, no watermarks, no low-res upscales, nothing behind logins or paywalls. Prefer free-license sources.

    ## How to add a wallpaper
    ```sh
    curl -L -A "Mozilla/5.0 (Macintosh)" -e "<page url>" \\
      -o "Static/Mountains - Alpine lake at dawn.jpg" "<direct file url>"
    file "Static/Mountains - Alpine lake at dawn.jpg"   # must say image data / ISO Media
    ```
    Delete anything that is HTML, an error page, or under 100 KB, and find a replacement.

    ## Rules
    - Only add files. Never rename, move or delete existing files unless the user asks.
    - List the folder first and skip wallpapers that are already here. Don't save the same wallpaper twice, even at another size; Aura moves exact and near-identical copies to the Trash anyway.
    - Do not create other folders or files here.
    - End with a table: file, resolution, source page, creator.
    """

    /// Writes AGENTS.md (kept up to date while it is still Aura's own file) and the CLAUDE.md/GEMINI.md imports.
    static func install() {
        let root = LibraryStore.root
        let agents = root.appending(path: "AGENTS.md")
        let existing = try? String(contentsOf: agents, encoding: .utf8)
        if existing == nil || (existing!.hasPrefix(header) && existing != agentsMD) {
            try? agentsMD.write(to: agents, atomically: true, encoding: .utf8)
        }
        for name in ["CLAUDE.md", "GEMINI.md"] { // Claude Code and Gemini CLI import syntax
            let url = root.appending(path: name)
            if !FileManager.default.fileExists(atPath: url.path) { try? "@AGENTS.md\n".write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}

struct DownloadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Downloader {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// Downloads one image or video into the library as "<collection> - <title>.<ext>".
    @MainActor
    static func fetch(_ source: URL, collection: String, title: String? = nil) async throws -> URL {
        var request = URLRequest(url: source, timeoutInterval: 120)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (tmp, response) = try await URLSession.shared.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else { throw DownloadError(message: "Server said \(status)") }
        let mime = response.mimeType ?? ""
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? source.pathExtension
        guard let kind = Wallpaper.kind(forExtension: ext) ?? Wallpaper.kind(forExtension: source.pathExtension) else {
            throw DownloadError(message: mime.contains("html") ? "That's a web page, not a file" : "Not an image or video (\(mime))")
        }
        let size = (try? tmp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 30_000 else { throw DownloadError(message: "File too small (\(Int64(size).fileSize))") }

        let library = LibraryStore.shared
        let name = LibraryStore.sanitize(title ?? String(source.deletingPathExtension().lastPathComponent.prefix(40)))
        let dest = library.uniqueURL(in: LibraryStore.folder(for: kind), base: "\(collection) - \(name)", ext: ext.lowercased())
        try FileManager.default.moveItem(at: tmp, to: dest)
        let floor = MinQuality.current
        if let wallpaper = Wallpaper(url: dest), let pixels = await Images.pixelSize(wallpaper), !floor.accepts(pixels) {
            try? FileManager.default.removeItem(at: dest)
            throw DownloadError(message: "Only \(Int(pixels.width))×\(Int(pixels.height)), below \(floor.title)")
        }
        library.exemptFromQuality.insert(dest.path)
        library.reload()
        return dest
    }
}

struct DownloadJob: Identifiable {
    enum State { case running, done(String), failed(String) }
    let id = UUID()
    let source: URL
    var state: State = .running
}

/// The "Get Wallpapers" flow: build a prompt, then collect what the agent finds.
@MainActor @Observable
final class AgentStudio {
    static let shared = AgentStudio()

    var subject = UserDefaults.standard.string(forKey: "studioSubject") ?? "" {
        didSet { UserDefaults.standard.set(subject, forKey: "studioSubject") }
    }
    var hints = ""
    var kind: WallpaperKind = .still
    var count = 6
    var agent: AgentTarget = AgentTarget(rawValue: UserDefaults.standard.string(forKey: "studioAgent") ?? "") ?? .claudeCode {
        didSet { UserDefaults.standard.set(agent.rawValue, forKey: "studioAgent") }
    }
    var jobs: [DownloadJob] = []
    var lastCopied: Date?
    /// Set when a notification asks to bring Get Wallpapers to the front.
    var showRequested: Date?
    let acp = ACPSession()

    /// Sends the prompt straight to the agent over ACP.
    func runNow() {
        Task { await acp.run(agent, prompt: prompt) }
    }

    var prompt: String { PromptBuilder.make(subject: subject, hints: hints, kind: kind, count: count, agent: agent) }
    var canCopy: Bool { !subject.trimmingCharacters(in: .whitespaces).isEmpty }

    func copyPrompt(open: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        lastCopied = .now
        if open, let url = agent.destination { NSWorkspace.shared.open(url) }
    }

    /// Reads an agent reply from the clipboard and downloads every link in it.
    func pasteReply() {
        let links = Self.links(in: NSPasteboard.general.string(forType: .string) ?? "")
        guard !links.isEmpty else {
            jobs = [DownloadJob(source: URL(string: "about:clipboard")!, state: .failed("No links found on the clipboard. Copy the agent's whole reply first."))]
            return
        }
        let collection = LibraryStore.sanitize(subject).isEmpty ? "Unsorted" : LibraryStore.sanitize(subject).capitalized
        jobs = links.map { DownloadJob(source: $0) }
        for job in jobs {
            Task {
                do {
                    let dest = try await Downloader.fetch(job.source, collection: collection)
                    update(job.id, .done(dest.lastPathComponent))
                } catch {
                    update(job.id, .failed(error.localizedDescription))
                }
            }
        }
    }

    static func links(in text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var seen = Set<URL>()
        return matches.compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && seen.insert($0).inserted }
            .prefix(30).map { $0 }
    }

    private func update(_ id: UUID, _ state: DownloadJob.State) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].state = state }
    }
}
