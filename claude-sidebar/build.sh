#!/bin/bash
# Builds build/ClaudeSidebar.app. Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeSidebar"
APP="build/ClaudeSidebar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeSidebar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo
echo "Built $APP"
echo "Run it:      open $APP"
echo "Install it:  cp -R $APP /Applications/"
