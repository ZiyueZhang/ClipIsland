#!/bin/bash
# Build ClipIsland.app without Xcode: SwiftPM release build + bundle assembly + adhoc codesign.
# Usage: build-app.sh [configuration] [version]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="${2:-1.1.0}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/ClipIsland"
APP="build/ClipIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipIsland"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipIsland</string>
    <key>CFBundleDisplayName</key><string>ClipIsland</string>
    <key>CFBundleIdentifier</key><string>com.clipisland.app</string>
    <key>CFBundleVersion</key><string>__VERSION__</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleExecutable</key><string>ClipIsland</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

sed -i '' "s/__VERSION__/$VERSION/g" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign failed, app is unsigned"

echo "Built $APP (v$VERSION)"
