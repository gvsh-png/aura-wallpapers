#!/bin/zsh
# Publishes a release that installed copies of Aura pick up through Customize → Updates.
# Usage: ./release.sh 1.2.0 "What changed"
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version> [notes]}
NOTES=${2:-"Aura $VERSION"}

echo "$VERSION" > VERSION
UNIVERSAL=1 ./build.sh --no-install
./make-installer.sh
# Aura 1.1.1–1.1.2 only know how to update from a zip; keep one for them.
rm -f build/Aura-update.zip
ditto -c -k --keepParent build/Aura.app build/Aura-update.zip

BODY="$NOTES

## Install
1. Download **Aura-Installer.pkg** below and open it.
2. If macOS says it can't check the installer for malicious software: open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then open the installer again. Aura isn't notarized by Apple yet, so this happens once.
3. Follow the installer. Aura opens when it's done.

Already have Aura? It updates itself: **Customize → Updates**. Requires macOS 15 or later (Apple silicon or Intel).
_Aura-update.zip is used by the in-app updater of older versions; you don't need it._"

git add VERSION
git commit -m "Release $VERSION" || true
git push
gh release create "v$VERSION" build/Aura-Installer.pkg build/Aura-update.zip --title "Aura $VERSION" --notes "$BODY"
echo "Released v$VERSION"
