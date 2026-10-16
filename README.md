# Aura

A native macOS wallpaper app for static and animated wallpapers. It builds a theme from your wallpaper and writes prompts so an AI agent can find new wallpapers for you.

## Features

- **Library.** Grid of static and animated wallpapers with hover previews, favorites, search and collections. Files live in `~/Pictures/Wallpapers/{Static,Live}` and are named `<Collection> - <Title>.<ext>`.
- **Animated wallpapers.** Video plays behind your desktop icons on every screen and Space.
- **Customize everything.**
  - Wallpaper: animation on/off, speed (0.25×–2×), sound and volume, scaling (fill, fit, stretch), dimming.
  - Power: pause when the desktop is covered, on battery, or in Low Power Mode. The display can still sleep.
  - Rotation: change the wallpaper every 15 minutes to every day, picking from all wallpapers, favorites, static only or animated only.
  - Theme: turn the accent color, text highlight, app-icon tint (subtle, balanced or vivid) and Light/Dark matching on or off one by one. Turning a part off restores the macOS default for it.
  - App: open at login, show or hide the menu bar icon.
- **Theme from your wallpaper.** Aura pulls a palette from the active wallpaper and applies it to macOS, either automatically or with one click. You can also copy the palette as CSS.
- **Get Wallpapers with any agent.** Describe what you want (a place, a mood, a style, anything), choose static or animated and pick an agent, then copy the prompt. Supported agents: Claude Code, Cursor, Codex, ChatGPT, Claude.ai and Gemini.
  - Coding agents download straight into the library. New files show up within seconds, marked **NEW**.
  - Chat agents reply with links. Copy the reply, click **Paste Reply**, and Aura downloads each file.
- **Agent instructions.** Aura writes `AGENTS.md` into the library folder, plus `CLAUDE.md` and `GEMINI.md` that import it. An agent opened there already knows the layout, naming and quality rules.
- **Starter pack.** On first launch with an empty library, Aura downloads a general set of landscapes, space, abstract, nature and city stills, plus ambient sky, water and abstract loops.
- **Sharing.** Use the share sheet or copy files, or export a selection as a `.zip` pack. Drop a pack (or images and videos) onto Aura to import it.
- **Design.** Frosted glass panels and buttons over a soft aurora drawn from your wallpaper's colors, the Geist typeface, and spring animations throughout. Cards tilt toward the pointer, and the grid and sections animate in. Reduce Motion is respected.
- **Menu bar.** Pause or resume, turn animation on/off, set speed, shuffle, and open favorites. Closing the window keeps the wallpaper running.

## Updates

Aura checks this repo's GitHub Releases every 6 hours (Customize → Updates, or right away with **Check Now**). When a newer `vX.Y.Z` release has an `Aura.zip` asset, Aura offers to update. It downloads the zip, checks the bundle ID and code signature, moves the old app to the Trash, puts the new one in its place and relaunches. `Aura --update` does the same from Terminal.

To publish a release:

```sh
./release.sh 1.2.0 "What changed"   # bumps VERSION, builds, zips, pushes, creates the GitHub release
```

The repository must be public for other people's copies to see releases.

## Build

Requires macOS 15+ and the Xcode Command Line Tools (Swift 6).

```sh
./build.sh               # builds, signs ad hoc, installs to /Applications and launches
./build.sh --no-install  # only builds build/Aura.app
```

## Layout

```
Sources/Aura/
  AuraApp.swift         app, menu bar, window opener
  Engine.swift          desktop picture, video/dim windows, pausing, rotation
  LibraryStore.swift    library folder, import/export, favorites
  Theme.swift           palette extraction + macOS theme writer
  Updater.swift         GitHub Releases updater + update UI
  Design.swift          font, glass, button style, tilt and appear motion
  Agents.swift          agent targets, prompt builder, AGENTS.md, downloader
  StarterPack.swift     first-run wallpaper list
  CustomizeView.swift   all settings
  *View.swift           other SwiftUI screens
Resources/Fonts/        Geist + Geist Mono (SIL Open Font License, see OFL.txt)
scripts/make-icon.swift renders the app icon
release.sh              publishes a GitHub release for the updater
```

## Notes

- Theme changes use `defaults write -g` for `AppleAccentColor`, `AppleHighlightColor` and the macOS 26 `AppleIconAppearance*` keys. Changing the icon tint restarts the Dock.
- The starter pack is downloaded from its sources at runtime, not bundled: stills from wallhaven.cc and videos from mixkit.co under the Mixkit License. Respect creators' licenses when you share wallpapers.

## License

Aura's code is released under the [MIT License](LICENSE). The bundled Geist and Geist Mono fonts are licensed separately under the [SIL Open Font License 1.1](Resources/Fonts/OFL.txt). Starter-pack wallpapers are not part of this repository and keep their creators' licenses.
