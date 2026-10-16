import SwiftUI

/// Every setting in one place. Shown in the main window (sidebar → Customize) and as the Settings window.
struct CustomizeView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage(Prefs.animate) private var animate = true
    @AppStorage(Prefs.speed) private var speed = 1.0
    @AppStorage(Prefs.scaling) private var scaling = Scaling.fill.rawValue
    @AppStorage(Prefs.dim) private var dim = 0.0
    @AppStorage(Prefs.sound) private var sound = false
    @AppStorage(Prefs.volume) private var volume = 0.5
    @AppStorage(Prefs.pauseWhenCovered) private var pauseWhenCovered = true
    @AppStorage(Prefs.pauseOnBattery) private var pauseOnBattery = false
    @AppStorage(Prefs.pauseInLowPower) private var pauseInLowPower = true
    @AppStorage(Prefs.rotateMinutes) private var rotateMinutes = 0
    @AppStorage(Prefs.rotateSource) private var rotateSource = RotateSource.all.rawValue
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Play animated wallpapers", isOn: $animate)
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $speed, in: 0.25...2, step: 0.05)
                        Text(speed.formatted(.number.precision(.fractionLength(2))) + "×")
                            .monospacedDigit().frame(width: 48, alignment: .trailing)
                        Button("Reset") { speed = 1 }.disabled(speed == 1)
                    }
                }
                .disabled(!animate)
                Toggle("Play sound", isOn: $sound).disabled(!animate)
                if sound && animate {
                    LabeledContent("Volume") { Slider(value: $volume, in: 0...1) }
                }
                Picker("Scaling", selection: $scaling) {
                    ForEach(Scaling.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Dim") {
                    HStack {
                        Slider(value: $dim, in: 0...0.7)
                        Text("\(Int((dim * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                }
            } header: {
                Text("Wallpaper")
            } footer: {
                Text("With animation off, animated wallpapers show a still frame.").foregroundStyle(.secondary)
            }

            Section("Power") {
                Toggle("Pause when the desktop is covered", isOn: $pauseWhenCovered)
                Toggle("Pause on battery power", isOn: $pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $pauseInLowPower)
            }

            Section("Rotation") {
                Picker("Change wallpaper", selection: $rotateMinutes) {
                    Text("Never").tag(0)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Every 3 hours").tag(180)
                    Text("Every day").tag(1440)
                }
                Picker("Pick from", selection: $rotateSource) {
                    ForEach(RotateSource.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .disabled(rotateMinutes == 0)
            }

            Section("Theme") { ThemeOptions() }

            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in LoginItem.setEnabled(on) }
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            } header: {
                Text("App")
            } footer: {
                Text("With the menu bar icon hidden, open Aura from Applications to get back here.").foregroundStyle(.secondary)
            }

            Section("Updates") { UpdateSettings() }

            Section("Library") {
                LabeledContent("Folder", value: "~/Pictures/Wallpapers")
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.open(LibraryStore.root) }
                    Button("Open AGENTS.md") { NSWorkspace.shared.open(LibraryStore.root.appending(path: "AGENTS.md")) }
                    Spacer()
                    if library.installingStarter { ProgressView().controlSize(.small) }
                    Button("Download Starter Pack") { library.installStarterPack() }
                        .disabled(library.installingStarter)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// Which parts of macOS the wallpaper theme touches. Turning a part off restores the macOS default for it.
struct ThemeOptions: View {
    @Environment(WallpaperEngine.self) private var engine
    @AppStorage(Prefs.autoTheme) private var autoTheme = true
    @AppStorage(Prefs.themeAccent) private var themeAccent = true
    @AppStorage(Prefs.themeHighlight) private var themeHighlight = true
    @AppStorage(Prefs.tintIcons) private var tintIcons = true
    @AppStorage(Prefs.tintStrength) private var tintStrength = TintStrength.balanced.rawValue
    @AppStorage(Prefs.matchAppearance) private var matchAppearance = false

    var body: some View {
        Toggle("Follow the wallpaper automatically", isOn: $autoTheme)
        Toggle("Accent color", isOn: $themeAccent)
            .onChange(of: themeAccent) { _, on in on ? reapply() : ThemeManager.resetAccent() }
        Toggle("Text highlight color", isOn: $themeHighlight)
            .onChange(of: themeHighlight) { _, on in on ? reapply() : ThemeManager.resetHighlight() }
        Toggle("Tint app icons and folders", isOn: $tintIcons)
            .onChange(of: tintIcons) { _, on in on ? reapply() : ThemeManager.resetIcons() }
        Picker("Icon tint strength", selection: $tintStrength) {
            ForEach(TintStrength.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .disabled(!tintIcons)
        .onChange(of: tintStrength) { reapply() }
        Toggle("Match Light/Dark mode to the wallpaper", isOn: $matchAppearance)
            .onChange(of: matchAppearance) { _, on in if on { reapply() } }
    }

    private func reapply() {
        if autoTheme, let palette = engine.palette { ThemeManager.apply(palette) }
    }
}
