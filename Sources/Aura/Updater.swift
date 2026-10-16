import AppKit
import SwiftUI
import Observation

/// Updates from GitHub Releases: finds a newer `vX.Y.Z` tag, takes Aura.app out of its installer
/// package (or update zip on older releases), swaps the bundle in place (old copy goes to the Trash) and relaunches.
/// No admin password needed: the package is unpacked, not run.
@MainActor @Observable
final class Updater {
    static let shared = Updater()
    static let repo = "gvsh-png/aura-wallpapers"

    struct Release: Equatable {
        let version: String
        let notes: String
        let asset: URL
        let assetName: String
        let page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), downloading, installing, failed(String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var timer: Timer?

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// The `updateFeed` default overrides the release URL (forks, testing).
    private var feed: URL {
        URL(string: UserDefaults.standard.string(forKey: "updateFeed") ?? "https://api.github.com/repos/\(Self.repo)/releases/latest")!
    }

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    /// Background check at most every 6 hours, when automatic checks are on.
    func checkIfDue() {
        guard Prefs.bool(Prefs.autoUpdateCheck), state == .idle || state == .upToDate else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date.now.timeIntervalSince1970 - last > 6 * 3600 else { return }
        Task { await check() }
    }

    func check() async {
        state = .checking
        do {
            var request = URLRequest(url: feed, timeoutInterval: 30)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw DownloadError(message: status == 404 ? "No public release found" : "Update server said \(status)")
            }
            let gh = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastUpdateCheck")
            let version = gh.tag_name.hasPrefix("v") ? String(gh.tag_name.dropFirst()) : gh.tag_name
            guard Self.isNewer(version, than: currentVersion),
                  let asset = gh.assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") })
                    ?? gh.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
                state = .upToDate
                return
            }
            state = .available(Release(version: version, notes: gh.body ?? "", asset: asset.browser_download_url,
                                       assetName: asset.name, page: gh.html_url))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func install(_ release: Release) async {
        state = .downloading
        do {
            let (download, _) = try await URLSession.shared.download(from: release.asset)
            state = .installing
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appending(path: "AuraUpdate-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let unpacked = work.appending(path: "unpacked")
            let ok = release.assetName.lowercased().hasSuffix(".pkg")
                ? Shell.run("/usr/sbin/pkgutil", ["--expand-full", download.path, unpacked.path]) == 0
                : Shell.run("/usr/bin/ditto", ["-x", "-k", download.path, unpacked.path]) == 0
            guard ok else { throw DownloadError(message: "Couldn't unpack the update") }

            let found = fm.enumerator(at: unpacked, includingPropertiesForKeys: nil)?
                .first { ($0 as? URL)?.lastPathComponent == "Aura.app" } as? URL
            guard let fresh = found, let bundle = Bundle(url: fresh), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw DownloadError(message: "The download isn't Aura")
            }
            guard Shell.run("/usr/bin/codesign", ["--verify", "--deep", fresh.path]) == 0 else {
                throw DownloadError(message: "The update's signature is broken")
            }
            Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])

            let target = Bundle.main.bundleURL
            var trashed: NSURL?
            try fm.trashItem(at: target, resultingItemURL: &trashed)
            do {
                try fm.moveItem(at: fresh, to: target)
            } catch {
                if let old = trashed as URL? { try? fm.moveItem(at: old, to: target) } // put the old version back
                throw error
            }
            relaunch(target)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Waits for this process to exit, then opens the new bundle.
    private func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }
}

/// Banner shown at the top of the main window when an update is ready.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        if let release = updater.available {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(.tint)
                    .symbolEffect(.bounce, options: .repeat(2), value: release.version)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aura \(release.version) is available").font(.aura(.headline))
                    Text("You have \(updater.currentVersion). It installs in place and relaunches.").font(.aura(.callout)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("What's New") { NSWorkspace.shared.open(release.page) }.buttonStyle(.glass)
                Button("Update") { Task { await updater.install(release) } }.buttonStyle(.glassProminent)
            }
            .padding(14)
            .glass(cornerRadius: 16, tint: .accentColor)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if updater.state == .downloading || updater.state == .installing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(updater.state == .downloading ? "Downloading update…" : "Installing… Aura will relaunch.").font(.aura(.callout, .medium))
            }
            .padding(12)
            .glass(cornerRadius: 14)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Updates section for Settings.
struct UpdateSettings: View {
    @Environment(Updater.self) private var updater
    @AppStorage(Prefs.autoUpdateCheck) private var autoCheck = true

    var body: some View {
        LabeledContent("Version", value: updater.currentVersion)
        Toggle("Check for updates automatically", isOn: $autoCheck)
        HStack {
            Group {
                switch updater.state {
                case .idle: Text("Not checked yet")
                case .checking: Text("Checking…")
                case .upToDate: Label("You're up to date", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                case .available(let r): Label("Version \(r.version) is available", systemImage: "sparkles").foregroundStyle(.tint)
                case .downloading: Text("Downloading…")
                case .installing: Text("Installing…")
                case .failed(let why): Label(why, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.aura(.callout))
            .contentTransition(.opacity)
            Spacer()
            if updater.state == .checking || updater.state == .downloading || updater.state == .installing {
                ProgressView().controlSize(.small)
            }
            if let release = updater.available {
                Button("Install & Relaunch") { Task { await updater.install(release) } }.buttonStyle(.glassProminent)
            } else {
                Button("Check Now") { Task { await updater.check() } }
                    .buttonStyle(.glass)
                    .disabled(updater.state == .checking)
            }
        }
        .animation(.auraSpring, value: updater.state)
    }
}
