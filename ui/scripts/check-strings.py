#!/usr/bin/env python3
"""Check the two translation tables in Strings.swift cover the same keys.

A missing key renders as the raw key in the UI, which is easy to ship by
accident. This fails loudly instead. Run: python3 ui/scripts/check-strings.py
"""
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "Sources/HermesKeychainMenu/Strings.swift"


def keys_of(table: str, text: str) -> set:
    """Keys declared in `static let <table>: [String: String] = [ ... ]`."""
    m = re.search(rf"static let {table}: \[String: String\] = \[(.*?)\n    \]", text, re.S)
    if not m:
        sys.exit(f"FAIL: table '{table}' not found in {SRC.name}")
    return set(re.findall(r'^\s*"([^"]+)":', m.group(1), re.M))


def main() -> int:
    text = SRC.read_text(encoding="utf-8")
    en, fr = keys_of("english", text), keys_of("french", text)

    missing_fr, missing_en = sorted(en - fr), sorted(fr - en)
    for k in missing_fr:
        print(f"  missing in french: {k}")
    for k in missing_en:
        print(f"  missing in english: {k}")

    if missing_fr or missing_en:
        print(f"\nFAIL: {len(missing_fr) + len(missing_en)} key(s) out of sync")
        return 1
    print(f"OK: {len(en)} keys, both languages in sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
