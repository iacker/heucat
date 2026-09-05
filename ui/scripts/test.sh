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

RUNNER_BIN="${TMPDIR:-/tmp}/hermes-keychain-runner-test"
swiftc \
  "$ROOT/Sources/HermesKeychainMenu/HermesRunner.swift" \
  "$ROOT/Tests/HermesRunnerSelfTest.swift" \
  -o "$RUNNER_BIN"
"$RUNNER_BIN"
rm -f "$RUNNER_BIN"

# The Swift enum and chthonios' cli.py describe the same exit codes; a rename on
# one side would silently mislabel every failure in the UI.
python3 "$ROOT/scripts/check-exit-codes.py"
python3 "$ROOT/scripts/check-strings.py"
