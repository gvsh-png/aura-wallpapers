#!/bin/zsh
# Builds a universal Aura, wraps it in an installer package and publishes a GitHub release.
# Usage: ./release.sh 1.2.0 "What changed"
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version> [notes]}
NOTES=${2:-"Aura $VERSION"}

echo "$VERSION" > VERSION
UNIVERSAL=1 ./build.sh --no-install
./make-installer.sh

BODY="$NOTES

## Install
**Terminal (quickest):**
\`\`\`
curl -fsSL https://raw.githubusercontent.com/gvsh-png/aura-wallpapers/main/install.sh | sh
\`\`\`

**Browser:**
1. Download **Aura-Installer.pkg** below and open it.
2. If macOS says it can't check the installer for malicious software: open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then open the installer again. Aura isn't notarized by Apple yet, so this happens once.
3. Follow the installer. Aura opens when it's done.

Requires macOS 15 or later (Apple silicon or Intel)."

git add VERSION
git commit -m "Release $VERSION" || true
git push
gh release create "v$VERSION" build/Aura-Installer.pkg --title "Aura $VERSION" --notes "$BODY"
echo "Released v$VERSION"
