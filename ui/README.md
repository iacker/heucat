# HEUCAT.app

Menu-bar app, French UI, under 1 MB on disk. No Dock icon, no main window: one popover.

| Tab | What it does | Backed by |
|---|---|---|
| Clés | keychain secrets per Hermes profile: status, Touch ID unlock, lock, add, delete | `heucat.py` (plugin CLI, no Hermes boot) |
| Profils | seal / open / re-lock a profile's `.env` (passphrase or YubiKey) | `chthonios seal/unseal/lock` |
| Coffres | encrypt any folder or file (Obsidian vault, whole profile) or a Hindsight bank into `~/Coffres`; open or restore | `chthonios pack/unpack`, Hindsight transfer API |

Secrets, passphrases and PINs only ever travel on stdin. The app never deletes an original.
A Hindsight bank is exported, sealed (the plaintext zip is shredded) and restores into a *new*
bank, so the live one is never touched. YubiKey vaults open from a terminal: the app copies the command.

```bash
ui/scripts/build-app.sh             # ui/dist/HEUCAT.app
ui/scripts/build-app.sh --install   # /Applications/HEUCAT.app, nothing left in dist
HEUCAT_SNAPSHOT=out.png HEUCAT_TAB=Coffres /Applications/HEUCAT.app/Contents/MacOS/HEUCAT   # offscreen render
```

Ad-hoc signed for local use; a distributable build needs a Developer ID and notarization.
