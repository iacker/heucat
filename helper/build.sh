#!/bin/bash
# Build the enclave helper with an embedded Info.plist so macOS grants
# LocalAuthentication biometry. Without the embedded plist the binary is an
# anonymous CLI and canEvaluatePolicy(.biometrics) returns false -> Touch ID
# never fires and unlock silently falls back to the login password.
set -euo pipefail
cd "$(dirname "$0")"

OUT=hermes-keychain-helper

swiftc -O main.swift -o "$OUT" \
  -framework LocalAuthentication -framework CryptoKit -framework Security \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist

# ponytail: ad-hoc signing (-s -). A real Developer ID cert ($99/yr) would also
# work but is overkill for a personal tool; embedded plist + ad-hoc is enough
# for biometry on Apple Silicon. Upgrade to Developer ID if you ever notarize.
codesign --force --sign - --identifier com.hermes.keychain-helper "$OUT"

echo "built $OUT"
codesign -dv "$OUT" 2>&1 | grep -E "Identifier|Signature"
otool -l "$OUT" | grep -q "__info_plist" && echo "info_plist embedded: yes"
