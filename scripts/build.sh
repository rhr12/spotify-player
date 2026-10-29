#!/usr/bin/env bash
# Builds SpotiMusic.app (Release, ad-hoc signed) into build/.
# Requires Xcode 15+ and XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
rm -rf build/SpotiMusic.xcarchive build/SpotiMusic.app
xcodebuild \
  -project SpotiMusic.xcodeproj \
  -scheme SpotiMusic \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/SpotiMusic.xcarchive \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  -quiet \
  archive
cp -R build/SpotiMusic.xcarchive/Products/Applications/SpotiMusic.app build/
echo "Built build/SpotiMusic.app"
