# Aura

A native macOS wallpaper app for static and animated wallpapers. It builds a theme from your wallpaper and writes prompts so an AI agent can find new wallpapers for you.

## Features

- **Library.** Grid of static and animated wallpapers with hover previews, favorites, search and collections. Files live in `~/Pictures/Wallpapers/{Static,Live}` and are named `<Collection> - <Title>.<ext>`.
- **Animated wallpapers.** Video plays behind your desktop icons on every screen and Space.
- **Settings for everything.**
  - Wallpaper: animation on/off, speed (0.25×–2×), sound and volume, scaling (fill, fit, stretch), dimming.
  - Power: pause when the desktop is covered, on battery, or in Low Power Mode. The display can still sleep.
  - Rotation: change the wallpaper every 15 minutes to every day, picking from all wallpapers, favorites, static only or animated only.
  - Theme: turn the accent color, text highlight, app-icon tint (subtle, balanced or vivid, off by default) and Light/Dark matching on or off one by one. Aura saves your own settings before it changes anything, and turning a part off puts yours back.
  - Turn off Aura's wallpaper (from the sidebar card, the menu bar or Settings) and your own desktop picture comes back.
  - App: open at login, show or hide the menu bar icon.
- **Theme from your wallpaper.** Aura pulls a palette from the active wallpaper and applies it to macOS, either automatically or with one click. You can also copy the palette as CSS.
- **4K quality.** A minimum download quality (default 4K) is written into agent prompts and enforced: downloads from agents, pasted links and the starter pack below it go to the Trash. Your own imports are never filtered. Cards show 8K/5K/4K/1440p/1080p badges.
- **Light playback.** Animated wallpapers play from an optimized copy made once with the hardware HEVC encoder, at most 4K (or 1080p to save battery) and capped at 30 fps. You can set the quality for each wallpaper in the inspector. The app window doesn't redraw anything while idle.
- **Full-screen preview.** Press Space, use the Preview button, or right-click → Preview Full Screen to see a wallpaper exactly as it will look. ←/→ browse, Return sets it, Esc closes.
- **No duplicates.** Each new download is checked against the library: exact copies, or the same picture or clip at another size or encoding, go to the Trash, and Aura tells you how many it skipped. Agents are told to skip what's already there too.
- **Get Wallpapers with any agent.** Describe what you want (a place, a mood, a style, anything), choose static or animated and pick an agent. Supported agents: Claude Code, Codex, Gemini CLI, Cursor, ChatGPT, Claude.ai and Gemini.
  - **Run Now (Agent Client Protocol):** with Claude Code, Codex or Gemini CLI, Aura sends the prompt straight to the agent over [ACP](https://agentclientprotocol.com). You watch its progress live and approve each download it wants to run (or **Allow All** for that run). If Aura is in the background, a notification lets you Allow, Allow All or Deny without switching apps. Claude Code and Codex start through `npx` (Node.js needed), and you must already be signed in to the agent.
  - Coding agents download straight into the library. New files show up within seconds, marked **NEW**.
  - Chat agents reply with links. Copy the reply, click **Paste Reply**, and Aura downloads each file.
- **Agent instructions.** Aura writes `AGENTS.md` into the library folder, plus `CLAUDE.md` and `GEMINI.md` that import it. An agent opened there already knows the layout, naming and quality rules.
- **Starter pack.** On first launch with an empty library, Aura downloads a random 1–4 stills (landscapes, space, abstract, nature, cities) and 1–4 ambient loops (sky, water, abstract). **Download Starter Pack** in Settings adds another random handful.
- **Sharing.** Use the share sheet or copy files, or export a selection as a `.zip` pack. Drop a pack (or images and videos) onto Aura to import it.
- **Design.** Frosted glass panels and buttons over a soft aurora drawn from your wallpaper's colors, the Geist typeface, and spring animations throughout. Cards tilt toward the pointer, and the grid and sections animate in. Reduce Motion is respected.
- **Menu bar.** Pause or resume, turn animation on/off, set speed, shuffle, and open favorites. Closing the window keeps the wallpaper running.

## Install

**From Terminal** (no Gatekeeper prompt):

```sh
curl -fsSL https://raw.githubusercontent.com/gvsh-png/aura-wallpapers/main/install.sh | sh
```

Or just download the installer and open it:

```sh
curl -fLO https://github.com/gvsh-png/aura-wallpapers/releases/latest/download/Aura-Installer.pkg && open Aura-Installer.pkg
```

**From the browser:**

1. Download **Aura-Installer.pkg** from the [latest release](https://github.com/gvsh-png/aura-wallpapers/releases/latest) and open it.
2. If macOS says it can't check the installer: open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then open the installer again. Aura isn't notarized by Apple yet, so this happens once.
3. Follow the installer. Aura opens when it's done.

Requires macOS 15 or later on Apple silicon or Intel.

## Updates

Aura checks this repo's GitHub Releases every 6 hours (Settings → Updates, or right away with **Check Now**). When a newer `vX.Y.Z` release exists, Aura offers to update. It downloads the installer package and unpacks it without running it, so no admin password is needed. Then it checks the bundle ID and code signature, moves the old app to the Trash, puts the new one in its place and relaunches. `Aura --update` does the same from Terminal.

To publish a release:

```sh
./release.sh 1.2.0 "What changed"   # bumps VERSION, builds universal, makes the .pkg, pushes, creates the GitHub release
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
  ACP.swift             Agent Client Protocol client (JSON-RPC over stdio)
  StarterPack.swift     first-run wallpaper list
  SettingsView.swift    all settings
  *View.swift           other SwiftUI screens
Resources/Fonts/        Geist + Geist Mono (SIL Open Font License, see OFL.txt)
scripts/make-icon.swift renders the app icon
installer/              Installer package: distribution, welcome/conclusion pages, pre/postinstall scripts
install.sh              one-line Terminal installer (curl | sh)
make-installer.sh       wraps build/Aura.app into build/Aura-Installer.pkg
release.sh              publishes a GitHub release for the updater
```

## Notes

- Theme changes use `defaults write -g` for `AppleAccentColor`, `AppleHighlightColor` and the macOS 26 `AppleIconAppearance*` keys. Changing the icon tint restarts the Dock.
- The starter pack is downloaded from its sources at runtime, not bundled: stills from wallhaven.cc and videos from mixkit.co under the Mixkit License. Respect creators' licenses when you share wallpapers.

## License

Aura's code is released under the [MIT License](LICENSE). The bundled Geist and Geist Mono fonts are licensed separately under the [SIL Open Font License 1.1](Resources/Fonts/OFL.txt). Starter-pack wallpapers are not part of this repository and keep their creators' licenses.
