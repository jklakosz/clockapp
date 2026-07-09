#!/bin/bash
# Builds Clockapp.app (a menubar-only .app bundle) from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Clockapp"
BUNDLE_ID="com.jules.clockapp"
VERSION="0.4.0-rc.1"
CONFIG="${1:-release}"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
APP_DIR="dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "▸ Assembling bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>Clockapp</string>
</dict>
</plist>
PLIST

IDENTITY="Clockapp Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "▸ Signing with stable identity « $IDENTITY »…"
    codesign --force --deep --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
    echo "▸ Ad-hoc code signing (run ./scripts/create-signing-cert.sh to stop Keychain prompts)…"
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "  (codesign skipped)"
fi

echo "✅ Built $APP_DIR"
echo "   Run:  open \"$APP_DIR\""
