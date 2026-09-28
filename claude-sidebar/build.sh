#!/bin/bash
# Builds build/ClaudeSidebar.app. Needs Xcode or the Command Line Tools (xcode-select --install).
# Calls the Swift compiler directly instead of `swift build`, because SwiftPM is broken on
# some Command Line Tools installs ("Invalid manifest ... Undefined symbols").
set -euo pipefail
cd "$(dirname "$0")"
APP="build/ClaudeSidebar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "Compiling... (this can take a minute)"
swiftc -O Sources/ClaudeSidebar/*.swift -o "$APP/Contents/MacOS/ClaudeSidebar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo
echo "Built $APP"
echo "Run it:      open $APP"
echo "Install it:  cp -R $APP /Applications/"
