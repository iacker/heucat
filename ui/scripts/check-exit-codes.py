#!/usr/bin/env python3
"""The UI's exit codes must match the CLI's, or failures get mislabelled.

Two files in two languages describe one contract. Nothing but this check stops
someone renumbering EXIT_WRONG_SECRET in Python while Swift still reads 10.
"""
import re
import sys
from pathlib import Path

UI = Path(__file__).resolve().parents[1]
CLI = Path.home() / "Hermes-Workspaces/Demos/hermes-chthonios/chthonios/cli.py"
MODEL = UI / "Sources/HermesKeychainMenu/AppModel.swift"

# Python name -> Swift case name.
PAIRS = {
    "EXIT_OK": "ok",
    "EXIT_ERROR": "error",
    "EXIT_WRONG_SECRET": "wrongSecret",
    "EXIT_KEY_FAILED": "keyFailed",
    "EXIT_STATE": "badState",
    "EXIT_NOT_FOUND": "notFound",
    "EXIT_MISSING_DEP": "missingDependency",
}


def main() -> int:
    if not CLI.exists():
        print(f"skip: chthonios not checked out at {CLI}")
        return 0

    py = dict(re.findall(r"^(EXIT_\w+)\s*=\s*(\d+)", CLI.read_text(), re.M))
    swift = dict(re.findall(r"case (\w+) = (\d+)", MODEL.read_text()))

    bad = []
    for name, case in PAIRS.items():
        if name not in py:
            bad.append(f"{name} missing from cli.py")
        elif case not in swift:
            bad.append(f"case {case} missing from AppModel.swift")
        elif py[name] != swift[case]:
            bad.append(f"{name}={py[name]} but Swift .{case}={swift[case]}")

    if bad:
        print("EXIT CODE MISMATCH:")
        for b in bad:
            print("  -", b)
        return 1
    print(f"OK: {len(PAIRS)} exit codes agree between cli.py and AppModel.swift")
    return 0


if __name__ == "__main__":
    sys.exit(main())
