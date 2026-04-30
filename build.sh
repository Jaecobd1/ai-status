#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ClaudeStatus"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

if ! command -v swiftc &>/dev/null; then
    echo "Error: swiftc not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

echo "Building $APP_NAME..."

mkdir -p "$APP_BUNDLE/Contents/MacOS"

swiftc \
    -framework Cocoa \
    -O \
    "$SCRIPT_DIR/main.swift" \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeStatus</string>
    <key>CFBundleIdentifier</key>
    <string>com.jakedobler.claudestatus</string>
    <key>CFBundleName</key>
    <string>Claude Status</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✅ Built: $APP_BUNDLE"
echo ""
echo "Run now:    open '$APP_BUNDLE'"
echo "Install:    cp -r '$APP_BUNDLE' ~/Applications/"
echo "Auto-start: Add ~/Applications/$APP_NAME.app to System Settings > General > Login Items"
