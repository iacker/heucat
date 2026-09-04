#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UI="$ROOT/ui"
APP="$UI/dist/HEUCAT Keychain.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

cd "$UI"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"
cp ".build/release/HermesKeychainMenu" "$MACOS/HermesKeychainMenu"

# Rebuild the icon from source art when Pillow is available, otherwise reuse the
# committed .icns. Either way the bundle always ships an icon.
ICON_SRC="$UI/assets/icon-source.png"
ICON_OUT="$UI/assets/AppIcon.icns"
if [ -f "$ICON_SRC" ] && python3 -c "import PIL" 2>/dev/null; then
  python3 "$UI/scripts/make-icon.py" "$ICON_SRC" "$ICON_OUT" || true
fi
if [ -f "$ICON_OUT" ]; then
  cp "$ICON_OUT" "$CONTENTS/Resources/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>HEUCAT Keychain</string>
  <key>CFBundleExecutable</key><string>HermesKeychainMenu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.iacker.hermes-keychain</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>HEUCAT Keychain</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Release artifact. --sequesterRsrc strips com.apple.provenance xattrs that
# otherwise break the code seal after unzip.
ditto -c -k --keepParent --sequesterRsrc "$APP" "$UI/dist/HEUCAT-Keychain.zip"
echo "$APP"
