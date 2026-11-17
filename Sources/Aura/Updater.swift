import AppKit
import SwiftUI
import Observation

/// Updates from GitHub Releases: finds a newer `vX.Y.Z` tag, takes Aura.app out of its installer
/// package, swaps the bundle in place (old copy goes to the Trash) and relaunches.
/// No admin password needed: the package is unpacked, not run.
@MainActor @Observable
final class Updater {
    static let shared = Updater()
    static let repo = "gvsh-png/aura-wallpapers"

    struct Release: Equatable {
        let version: String
        let asset: URL
        let assetName: String
        let page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), downloading, installing, failed(String)
    }

    private(set) var state: State = .idle

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    var busy: Bool { state == .checking || state == .downloading || state == .installing }

    /// The `updateFeed` default overrides the release URL (forks, testing).
    private var feed: URL {
        URL(string: UserDefaults.standard.string(forKey: "updateFeed") ?? "https://api.github.com/repos/\(Self.repo)/releases/latest")!
    }

    /// Checks on launch, at most every 6 hours, when automatic checks are on. Aura doesn't run in the background.
    func checkIfDue() {
        guard UserDefaults.standard.bool(forKey: "autoUpdateCheck") else { return }
        guard Date.now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: "lastUpdateCheck") > 6 * 3600 else { return }
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
                throw Failure(message: status == 404 ? "No public release found" : "Update server said \(status)")
            }
            let gh = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastUpdateCheck")
            let version = gh.tag_name.hasPrefix("v") ? String(gh.tag_name.dropFirst()) : gh.tag_name
            guard Self.isNewer(version, than: currentVersion),
                  let asset = gh.assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") }) else {
                state = .upToDate
                return
            }
            state = .available(Release(version: version, asset: asset.browser_download_url, assetName: asset.name, page: gh.html_url))
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
            guard Shell.run("/usr/sbin/pkgutil", ["--expand-full", download.path, unpacked.path]) == 0 else {
                throw Failure(message: "Couldn't unpack the update")
            }
            let found = fm.enumerator(at: unpacked, includingPropertiesForKeys: nil)?
                .first { ($0 as? URL)?.lastPathComponent == "Aura.app" } as? URL
            guard let fresh = found, let bundle = Bundle(url: fresh), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw Failure(message: "The download isn't Aura")
            }
            guard Shell.run("/usr/bin/codesign", ["--verify", "--deep", fresh.path]) == 0 else {
                throw Failure(message: "The update's signature is broken")
            }
            Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])

            let target = Bundle.main.bundleURL
            if needsPassword {
                try Self.installWithAdminRights(fresh, over: target)
            } else {
                var trashed: NSURL?
                try fm.trashItem(at: target, resultingItemURL: &trashed)
                do {
                    try fm.moveItem(at: fresh, to: target)
                } catch {
                    if let old = trashed as URL? { try? fm.moveItem(at: old, to: target) } // put the old version back
                    throw error
                }
            }
            relaunch(target)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// True when the app is owned by root (installed with an old .pkg), so replacing it needs an admin password.
    var needsPassword: Bool {
        let app = Bundle.main.bundleURL
        let owner = (try? FileManager.default.attributesOfItem(atPath: app.path)[.ownerAccountID] as? NSNumber)?.uint32Value
        return owner != getuid() || !FileManager.default.isWritableFile(atPath: app.path)
    }

    /// Replaces the app through the standard macOS password prompt, then hands it to the user
    /// so later updates don't ask again.
    static func installWithAdminRights(_ fresh: URL, over target: URL) throws {
        func sh(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "/bin/rm -rf \(sh(target.path)) && /usr/bin/ditto \(sh(fresh.path)) \(sh(target.path)) && /usr/sbin/chown -R \(getuid()):staff \(sh(target.path))"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error else { return }
        let code = error[NSAppleScript.errorNumber] as? Int
        throw Failure(message: code == -128 ? "Update cancelled" : (error[NSAppleScript.errorMessage] as? String ?? "Couldn't replace the app"))
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
        let html_url: URL
        let assets: [Asset]
    }
}

/// Slim bar under the header while an update is ready or installing.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        if updater.available != nil || updater.state == .downloading || updater.state == .installing {
            HStack(spacing: 12) {
                if let release = updater.available {
                    Circle().fill(.tint).frame(width: 7, height: 7)
                    Text("Aura \(release.version) is ready").font(.sora(12.5, .semibold))
                    Text("You have \(updater.currentVersion)").font(.sora(12)).foregroundStyle(Matte.dim)
                    Spacer()
                    Button("What's New") { NSWorkspace.shared.open(release.page) }.buttonStyle(.matte)
                    Button("Update") { Task { await updater.install(release) } }.buttonStyle(.accent)
                } else {
                    ProgressView().controlSize(.small)
                    Text(updater.state == .downloading ? "Downloading update…" : "Installing. Aura will relaunch.").font(.sora(12.5, .medium))
                    Spacer()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Matte.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Matte.line))
            .padding(.horizontal, 20).padding(.bottom, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
