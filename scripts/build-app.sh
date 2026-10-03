#!/bin/zsh
# Builds ChoskyCare.app (release, ad-hoc signed) into ./dist.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="dist/ChoskyCare.app"
VERSION="0.2.0"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ChoskyCare" "$APP/Contents/MacOS/ChoskyCare"
# Bundle.module looks for the resource bundle in Contents/Resources.
cp -R "$BIN_DIR/ChoskyCare_ChoskyCare.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ChoskyCare</string>
    <key>CFBundleDisplayName</key><string>ChoskyCare</string>
    <key>CFBundleIdentifier</key><string>com.chosky.ChoskyCare</string>
    <key>CFBundleExecutable</key><string>ChoskyCare</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"
