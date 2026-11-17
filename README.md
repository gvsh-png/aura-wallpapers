# Aura

A small macOS app for static wallpapers. Search Wallhaven, download what you like, click to put it on your desktop.

## Features

- **Library.** Matte black grid of the images in `~/Pictures/Wallpapers/Static`, shaped like your screen. Click one and the desktop changes with a smooth fade, zoom and focus. Add your own images with **+** or by dropping them on the window.
- **Quick picker.** Press ⌃⌥W from any app for a full-screen coverflow of your wallpapers. ←/→ browse, ↩ sets, Esc closes.
- **Favorites and shuffle.** Heart the ones you love. Shuffle now, or change automatically every 15 minutes to once a day, from all wallpapers or only favorites.
- **Discover.** Search wallhaven.cc for a character, show, game or place, pick the ones you want and download them. SFW and landscape only.
- **Customize.** Brightness, contrast, saturation, blur and vignette, plus your own text and images placed anywhere on the picture. Saves a new full-size copy and sets it.
- **Theme from your wallpaper.** Aura's surfaces, accent and glow take the wallpaper's color, and so do the macOS accent and highlight colors (turn that off in Settings to get yours back). Type is Sora (SIL Open Font License).
- **Always a window.** No full screen. Aura keeps running quietly after you close the window so ⌃⌥W and auto shuffle work; turn that off in Settings and it quits with its window.
- **Updates from GitHub.** Aura checks this repo's releases when it opens (at most every 6 hours) and installs new versions in place.

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

## Build

Requires macOS 15+ and the Xcode Command Line Tools (Swift 6).

```sh
./build.sh               # builds, signs ad hoc, installs to /Applications and launches
./build.sh --no-install  # only builds build/Aura.app
./release.sh 2.0.0 "What changed"   # universal build, .pkg, GitHub release
```

## Layout

```
Sources/Aura/
  AuraApp.swift     app, window, one-time cleanup of 1.x leftovers
  Theme.swift       matte colors, Sora, palette from the wallpaper, buttons
  Library.swift     library folder, favorites, auto shuffle, desktop transition, thumbnail cache
  Picker.swift      ⌃⌥W quick picker
  ContentView.swift header, library grid, settings
  Editor.swift      adjustments and text/image layers
  Wallhaven.swift   Discover: Wallhaven search and downloads
  Updater.swift     GitHub Releases updates
```
