#!/usr/bin/env bash
# Packages build/SpotiMusic.app into a drag-to-Applications DMG (brew install create-dmg).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/SpotiMusic.app/Contents/Info.plist)}"
DMG="build/SpotiMusic-${VERSION}.dmg"
STAGING="build/dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/SpotiMusic.app "$STAGING/"

args=(
  --volname "SpotiMusic"
  --window-pos 200 120
  --window-size 600 380
  --icon-size 110
  --icon "SpotiMusic.app" 160 180
  --hide-extension "SpotiMusic.app"
  --app-drop-link 440 180
  --no-internet-enable
)

# Finder scripting (icon layout) can time out on headless CI; fall back to an unstyled DMG.
if ! create-dmg "${args[@]}" "$DMG" "$STAGING"; then
  echo "create-dmg with Finder layout failed; retrying without it"
  rm -f "$DMG" build/rw.*.dmg
  create-dmg --skip-jenkins "${args[@]}" "$DMG" "$STAGING"
fi
echo "Created $DMG"
