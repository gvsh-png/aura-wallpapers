#!/bin/zsh
# Builds Aura.app and installs it to /Applications. Usage: ./build.sh [--no-install]
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
swift build -c release
APP=build/Aura.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Aura "$APP/Contents/MacOS/Aura"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

# Icon
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Aura</string>
  <key>CFBundleDisplayName</key><string>Aura</string>
  <key>CFBundleIdentifier</key><string>com.aura.wallpapers</string>
  <key>CFBundleExecutable</key><string>Aura</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Aura switches Light/Dark mode to match your wallpaper.</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  pkill -x Aura 2>/dev/null || true
  rm -rf /Applications/Aura.app
  cp -R "$APP" /Applications/Aura.app
  open /Applications/Aura.app
  echo "Installed /Applications/Aura.app"
fi
