#!/bin/bash
set -e
DIR="$HOME/Scripts/spotlight-sens/app"
APP="$DIR/SpotlightSens.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O "$DIR/main.swift" -o "$APP/Contents/MacOS/SpotlightSens" \
  -framework Cocoa -framework Carbon
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SpotlightSens</string>
  <key>CFBundleIdentifier</key><string>com.vassili.spotlightsens</string>
  <key>CFBundleExecutable</key><string>SpotlightSens</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
echo "OK -> $APP"
