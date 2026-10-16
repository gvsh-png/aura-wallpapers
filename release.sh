#!/bin/zsh
# Publishes a release that installed copies of Aura pick up through Customize → Updates.
# Usage: ./release.sh 1.2.0 "What changed"
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version> [notes]}
NOTES=${2:-"Aura $VERSION"}

echo "$VERSION" > VERSION
./build.sh --no-install
rm -f build/Aura.zip
ditto -c -k --keepParent build/Aura.app build/Aura.zip

git add VERSION
git commit -m "Release $VERSION" || true
git push
gh release create "v$VERSION" build/Aura.zip --title "Aura $VERSION" --notes "$NOTES"
echo "Released v$VERSION"
