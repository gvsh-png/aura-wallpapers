#!/bin/zsh
# Wraps build/Aura.app in a macOS Installer package: build/Aura-Installer.pkg
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)

rm -rf build/pkgroot build/Aura-component.pkg build/Aura-Installer.pkg
mkdir -p build/pkgroot
cp -R build/Aura.app build/pkgroot/

# Always install to /Applications, even if another copy exists elsewhere.
pkgbuild --analyze --root build/pkgroot build/components.plist
plutil -replace 0.BundleIsRelocatable -bool NO build/components.plist

pkgbuild --root build/pkgroot --component-plist build/components.plist \
  --install-location /Applications --scripts installer/scripts \
  --identifier com.aura.wallpapers.pkg --version "$VERSION" \
  build/Aura-component.pkg

sed "s/__VERSION__/$VERSION/" installer/Distribution.xml > build/Distribution.xml
productbuild --distribution build/Distribution.xml --package-path build \
  --resources installer/resources build/Aura-Installer.pkg
echo "Built build/Aura-Installer.pkg"
