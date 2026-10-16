import SwiftUI

struct ThemeView: View {
    @Environment(WallpaperEngine.self) private var engine
    @State private var applied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Theme").font(.aura(size: 30, .bold))
                    Text("Colors from your wallpaper, applied to macOS: accent, text highlight, tinted app icons and Light/Dark mode.")
                        .foregroundStyle(.secondary)
                }
                if let current = engine.current, let palette = engine.palette {
                    hero(current, palette)
                    preview(palette)
                    options
                    actions(palette)
                } else {
                    Panel {
                        ContentUnavailableView("No wallpaper yet", systemImage: "paintpalette",
                                               description: Text("Set a wallpaper first. Its colors become your theme."))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Theme")
    }

    private func hero(_ w: Wallpaper, _ p: Palette) -> some View {
        Color.clear
            .aspectRatio(21 / 9, contentMode: .fit)
            .overlay { Thumbnail(wallpaper: w, size: 1200) }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 10) {
                    ForEach(p.colors, id: \.self) { Swatch(color: $0, size: 40) }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(nsColor: p.accent).opacity(0.35), radius: 24, y: 10)
    }

    private func preview(_ p: Palette) -> some View {
        let accent = Color(nsColor: p.accent)
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Preview").font(.aura(.title3, .bold))
                HStack(spacing: 18) {
                    Image(systemName: "folder.fill").font(.system(size: 44)).foregroundStyle(Color(nsColor: ThemeManager.iconTint(p.accent)))
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: ThemeManager.iconTint(p.accent)).gradient)
                        .frame(width: 50, height: 50)
                        .overlay(Image(systemName: "sparkles").font(.aura(.title2)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Button") {}.buttonStyle(.glassProminent)
                            Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
                            Text("Selected text").padding(.horizontal, 4).background(Color(nsColor: ThemeManager.highlight(p.accent)).opacity(0.6))
                        }
                        ProgressView(value: 0.65).frame(width: 260)
                    }
                    .tint(accent)
                }
                Text("macOS accent: \(ThemeManager.accentName(p.accent)) · Wallpaper is \(p.isDark ? "dark" : "light")")
                    .font(.aura(.callout)).foregroundStyle(.secondary)
            }
        }
    }

    private var options: some View {
        Form { ThemeOptions() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 300)
    }

    private func actions(_ p: Palette) -> some View {
        HStack {
            Button {
                ThemeManager.apply(p)
                applied = true
                Task { try? await Task.sleep(for: .seconds(2)); applied = false }
            } label: {
                Label(applied ? "Applied" : "Apply Theme", systemImage: applied ? "checkmark" : "paintbrush.pointed.fill").frame(minWidth: 150)
            }
            .buttonStyle(.glassProminent).controlSize(.extraLarge)
            Button("Copy as CSS") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(p.css, forType: .string)
            }
            .controlSize(.extraLarge)
            Spacer()
            Button("Restore My Original Look", role: .destructive) { ThemeManager.reset() }
                .help("Puts back the accent, highlight, icon style and Light/Dark mode you had before Aura")
                .controlSize(.large)
        }
    }
}
