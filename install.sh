#!/bin/sh
# Installs the latest Aura from GitHub Releases.
#   curl -fsSL https://raw.githubusercontent.com/gvsh-png/aura-wallpapers/main/install.sh | sh
set -e
dir=$(mktemp -d)
pkg="$dir/Aura-Installer.pkg"
echo "Downloading the latest Aura…"
curl -fL --progress-bar -o "$pkg" https://github.com/gvsh-png/aura-wallpapers/releases/latest/download/Aura-Installer.pkg
echo "Installing. macOS will ask for your password."
sudo /usr/sbin/installer -pkg "$pkg" -target /
rm -rf "$dir"
echo "Done. Aura is in Applications and opening now."
