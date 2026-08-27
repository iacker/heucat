#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TMPDIR:-/tmp}/hermes-keychain-status-test"
swiftc \
  "$ROOT/Sources/HermesKeychainMenu/StatusParser.swift" \
  "$ROOT/Tests/StatusParserSelfTest.swift" \
  -o "$BIN"
"$BIN"
rm -f "$BIN"
