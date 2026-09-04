# Hermes Keychain menu bar app

Native SwiftUI companion for the Apple Keychain + Secure Enclave plugin.

- Menu-bar lock state
- Per-secret mode and status
- Unlock through the native LocalAuthentication flow
- Lock all TTL sessions immediately
- Refresh and configurable Hermes binary/profile paths

The app does not implement secret storage. It delegates only
`hermes keychain status|unlock|lock` to the plugin CLI, keeping one security
implementation and avoiding secret values in process arguments.

## Build and run

```bash
cd ui
./scripts/test.sh
./scripts/build-app.sh
open "dist/HEUCAT Keychain.app"
```

Paths are detected on first launch (`hermes` on the usual install paths,
`HERMES_HOME` or `~/.hermes`) and can be changed in Settings:

- Hermes CLI: `~/.local/bin/hermes`
- Hermes home: `~/.hermes` (or `~/.hermes/profiles/<name>` for a profile)

The app is ad-hoc signed for local use. A distributable build would need an
Apple Developer ID signature and notarization.
