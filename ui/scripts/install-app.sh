#!/bin/bash
set -euo pipefail
UI="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$UI/dist/HEUCAT Keychain.app"
TARGET="/Applications/HEUCAT Keychain.app"
[ -d "$SOURCE" ] || { printf 'Build first: ./scripts/build-app.sh\n' >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE"
# Quit either copy before replacing the Finder/Spotlight installation.
osascript -e 'tell application id "dev.iacker.hermes-keychain" to quit' || true
for attempt in {1..20}; do
  pgrep -x HermesKeychainMenu >/dev/null || break
  sleep 0.2
done
if pgrep -x HermesKeychainMenu >/dev/null; then
  printf 'HEUCAT is still running. Quit it before installing.\n' >&2
  exit 1
fi
if [ -d "$TARGET" ]; then
  BACKUP="$HOME/Library/Application Support/HEUCAT/Backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP"
  mv "$TARGET" "$BACKUP/"
  printf 'Previous app: %s\n' "$BACKUP/HEUCAT Keychain.app"
fi
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
open "$TARGET"
printf 'Installed: %s\n' "$TARGET"
