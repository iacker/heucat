#!/bin/bash
# HEUCAT installer. Idempotent: run it again after a git pull.
#   git clone https://github.com/iacker/heucat && cd heucat && ./install.sh
set -euo pipefail
cd "$(dirname "$0")"
SRC="$PWD"
HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
PLUGIN="$HOME_DIR/plugins/keychain-secretsource"
CFG="$HOME_DIR/config.yaml"

[ "$(uname)" = Darwin ] || { echo "HEUCAT needs macOS"; exit 1; }
command -v hermes >/dev/null || { echo "hermes not found. Install Hermes Agent first: https://github.com/NousResearch/hermes-agent"; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc not found. Run: xcode-select --install"; exit 1; }

# 1. plugin: symlink the clone into the Hermes plugin dir
mkdir -p "$HOME_DIR/plugins"
if [ "$(readlink "$PLUGIN" 2>/dev/null)" != "$SRC" ] && [ "$PLUGIN" != "$SRC" ]; then
  [ -e "$PLUGIN" ] && { echo "$PLUGIN exists and is not this clone. Remove it first."; exit 1; }
  ln -s "$SRC" "$PLUGIN"
fi
echo "plugin  : $PLUGIN"

# 2. helper
(cd helper && bash build.sh >/dev/null) && echo "helper  : built"

# 3. config: never edit a user's YAML (a second top-level `plugins:` would
#    silently replace the first). Print the stanza instead.
if grep -q "keychain" "$CFG" 2>/dev/null; then
  echo "config  : keychain already mentioned in $CFG"
else
  cat <<YAML

config  : add this to $CFG (merge into existing plugins:/secrets: keys if present)

plugins:
  enabled:
    - keychain
secrets:
  sources: [keychain]
  keychain:
    enabled: true
YAML
fi

# 4. optional menu-bar app
if [ "${1:-}" = "--app" ]; then
  ui/scripts/build-app.sh >/dev/null
  rm -rf "/Applications/HEUCAT Keychain.app"
  ditto "ui/dist/HEUCAT Keychain.app" "/Applications/HEUCAT Keychain.app"
  echo "app     : /Applications/HEUCAT Keychain.app"
fi

echo
echo "Next: hermes keychain store OPENROUTER_API_KEY"
echo "      hermes keychain status"
