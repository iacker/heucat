# hermes-keychain-secretsource

Apple Keychain + **Secure Enclave** secret source for
[Hermes Agent](https://github.com/NousResearch/hermes-agent). Keep API keys
out of `.env` files: serve them from the macOS Keychain, and optionally
gate them behind **Touch ID / user-presence authentication** with
hardware-backed Secure Enclave encryption.

Runtime companion of
[hermes-chthonios](https://github.com/iacker/hermes-chthonios) — Chthonios
seals secrets *at rest*, this source *serves* them at execution.

## Two modes

| | `plain` | `enclave` |
|---|---|---|
| Storage | macOS Keychain generic password | Ciphertext file, key in Secure Enclave |
| Read requires | login session (or System keychain) | live user authentication (Touch ID / password / Watch) |
| Headless daemons | ✅ (System keychain) | ❌ by design |
| Startup prompt | never | never — out-of-band `hermes keychain unlock` |
| Value at rest | encrypted by keychain | ChaChaPoly, P256 key that never leaves the enclave |

**Why enclave mode matters:** a plain keychain item is readable by any
process running as you once the keychain is unlocked (which it is, all
day). An enclave item is unreadable until a human proves presence —
malware scraping your dotfiles or keychain gets ciphertext.

## Install

```bash
git clone https://github.com/iacker/hermes-keychain-secretsource \
    ~/.hermes/plugins/keychain-secretsource
```

Enable it in `~/.hermes/config.yaml` (the plugin key is `keychain`):

```yaml
plugins:
  enabled:
    - keychain
```

The Secure Enclave helper builds itself on first `store --enclave`
(needs Xcode Command Line Tools: `xcode-select --install`).

## Native menu bar app

The optional SwiftUI app in [`ui/`](ui/) shows source and per-secret state,
and runs unlock or lock without opening a terminal. It delegates security
operations to the same plugin CLI and never puts secret values in process
arguments.

```bash
cd ui
./scripts/test.sh
./scripts/build-app.sh
open "dist/Hermes Keychain.app"
```

The local build is ad-hoc signed. Public binary distribution requires a
Developer ID signature and Apple notarization.

## Quick start

```bash
# 1. Store secrets
hermes keychain store OPENROUTER_API_KEY              # plain
hermes keychain store GITHUB_TOKEN --enclave          # Secure Enclave

# 2. Reference them in config.yaml
```

```yaml
secrets:
  sources: [keychain]
  keychain:
    enabled: true
    accounts:                # plain mode, account name == env var
      - OPENROUTER_API_KEY
    items:
      - env: GITHUB_TOKEN
        mode: enclave
```

```bash
# 3. Enclave secrets: authenticate once per session (default 8h)
hermes keychain unlock

# 4. Check state
hermes keychain status
```

## How enclave mode works

```
store --enclave        unlock (once)              fetch (every startup)
  │                      │                          │
  ▼                      ▼                          ▼
P256 pubkey ──encrypt──▶ Touch ID ──decrypt──▶ session record ──▶ env vars
(no prompt)              ONE prompt for        (login keychain,   (silent)
                         the whole batch        TTL-bounded)
```

- `keygen` creates a P256 key **inside** the Secure Enclave, access-gated
  on user presence (`--strict-biometry` binds it to the currently
  enrolled fingerprints instead). The exported blob is useless on any
  other machine.
- `encrypt` needs only the public key — **no prompt** to add secrets.
- `unlock` authenticates **once** (a single LAContext for the whole
  batch), then caches plaintexts as TTL-bounded session records in the
  login keychain — encrypted at rest by macOS, never written to disk as
  plaintext, expired records self-delete.
- `fetch()` (the Hermes startup path) only ever reads session records.
  Locked secrets are a warning (or `AUTH_EXPIRED` with a remediation
  hint when nothing is readable), never a blocking prompt: gateway,
  cron, and subagent startups stay non-interactive by contract.

## Headless / daemon setups

Use plain mode with the System keychain (readable from any security
session, including launchd at boot):

```yaml
secrets:
  keychain:
    enabled: true
    default_keychain: /Library/Keychains/System.keychain
    accounts: [OPENROUTER_API_KEY]
```

```bash
sudo security add-generic-password -U -s hermes \
    -a OPENROUTER_API_KEY -w "$VALUE" /Library/Keychains/System.keychain
```

## Config reference (`secrets.keychain.*`)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Master switch |
| `service` | `hermes` | Keychain service name for plain items |
| `accounts` | `[]` | Env var names, plain mode, account == name |
| `items` | `[]` | Per-secret: `{env, mode: plain\|enclave, service?, account?, keychain?}` |
| `default_keychain` | `""` | Keychain file for plain reads (empty = search list) |
| `session_ttl_seconds` | `28800` | Enclave unlock validity (8h) |
| `timeout_seconds` | `30` | Fetch wall-clock budget |

## CLI

```
hermes keychain setup                 setup walkthrough
hermes keychain store <ENV> [--enclave] [--value V] [--service S] [--account A]
hermes keychain unlock                one auth, open all enclave sessions
hermes keychain lock                  clear sessions now
hermes keychain status                per-secret state
hermes keychain delete <ENV>          remove item + ciphertext + session
```

## Security model

- `fetch()` **never raises, never prompts, never writes `os.environ`** —
  the Hermes orchestrator owns precedence and application.
- All subprocess calls are argv-list with a minimal allowlisted env and
  stdin closed (`/usr/bin/security` can't prompt; a locked keychain
  fails fast).
- The Swift helper is ~200 lines, reviewable in one sitting
  (`helper/main.swift`), built locally, ad-hoc signed.
- Enclave ciphertexts and the key blob live under
  `$HERMES_HOME/keychain/` with mode `0600`. The blob without this
  machine's enclave + a live authentication decrypts nothing.
- Why not biometric Keychain ACLs directly? `SecAccessControl` biometric
  flags require the Data Protection keychain, which requires a paid
  Apple Developer application-identifier entitlement — impossible for an
  ad-hoc signed OSS CLI. The enclave-key design (same model as
  age-plugin-se) delivers the same guarantee without the entitlement.

## Tests

```bash
HERMES_AGENT_SRC=~/.hermes/hermes-agent \
  uv run --with pytest --with pyyaml --with rich python -m pytest tests/ -v
```

Hermetic (no real keychain/enclave touched) and includes the upstream
`SecretSourceConformance` kit. 26 tests.

## License

MIT
