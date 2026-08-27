#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UI="$ROOT/ui"
APP="$UI/dist/Hermes Keychain.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

cd "$UI"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS"
cp ".build/release/HermesKeychainMenu" "$MACOS/HermesKeychainMenu"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>Hermes Keychain</string>
  <key>CFBundleExecutable</key><string>HermesKeychainMenu</string>
  <key>CFBundleIdentifier</key><string>dev.iacker.hermes-keychain</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Hermes Keychain</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
