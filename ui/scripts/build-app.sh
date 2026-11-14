#!/bin/bash
# Build HEUCAT.app with plain swiftc: no SwiftPM, no .build cache, one binary.
#   ui/scripts/build-app.sh            -> ui/dist/HEUCAT.app
#   ui/scripts/build-app.sh --zip      -> also ui/dist/HEUCAT.zip (release artifact)
#   ui/scripts/build-app.sh --install  -> /Applications/HEUCAT.app, no copy left in dist
set -euo pipefail
UI="$(cd "$(dirname "$0")/.." && pwd)"
APP="$UI/dist/HEUCAT.app"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# SwiftUI macros need an SDK that ships their plugins (CLT 27's MacOSX27 SDK
# does not); pick the newest SDK that does instead of pinning a version.
if [ -z "${SDKROOT:-}" ]; then
  for sdk in "$(xcrun --show-sdk-path 2>/dev/null || true)" /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
    [ -d "$sdk" ] || continue
    printf 'import SwiftUI\nstruct P: View { @State var v = 0\n var body: some View { EmptyView() } }\n' \
      | swiftc -sdk "$sdk" -typecheck - >/dev/null 2>&1 && { export SDKROOT="$sdk"; break; }
  done
fi

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  "$UI"/Sources/HEUCAT/*.swift -o "$APP/Contents/MacOS/HEUCAT"
strip -x "$APP/Contents/MacOS/HEUCAT"

# Icon: three sizes cover Finder, Spotlight and the app switcher.
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 32 128 256; do
  sips -z $s $s "$UI/assets/icon-source.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$UI/assets/icon-source.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HEUCAT</string>
  <key>CFBundleDisplayName</key><string>HEUCAT</string>
  <key>CFBundleExecutable</key><string>HEUCAT</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.iacker.heucat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

case "${1:-}" in
  --zip)
    # --sequesterRsrc strips provenance xattrs that would break the seal after unzip.
    ditto -c -k --keepParent --sequesterRsrc "$APP" "$UI/dist/HEUCAT.zip"
    echo "$UI/dist/HEUCAT.zip" ;;
  --install)
    osascript -e 'quit app id "dev.iacker.heucat"' 2>/dev/null || true
    rm -rf /Applications/HEUCAT.app
    ditto "$APP" /Applications/HEUCAT.app
    rm -rf "$UI/dist"   # a single copy on disk, so Spotlight lists one HEUCAT
    echo /Applications/HEUCAT.app ;;
  *) echo "$APP" ;;
esac
