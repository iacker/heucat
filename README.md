# hermes-keychain-secretsource

Serve [Hermes Agent](https://github.com/NousResearch/hermes-agent) API keys from
the macOS Keychain instead of a plaintext `.env` file. Secrets you care about
more can sit behind Touch ID, encrypted with a key that never leaves the Secure
Enclave.

This is the runtime half of a pair. [hermes-chthonios](https://github.com/iacker/hermes-chthonios)
seals a whole profile at rest. This plugin hands individual secrets to a running
process.

## The problem

A Hermes `.env` file is a list of API keys in plaintext, mode 0600. That is fine
against another user account on the same Mac. It does nothing against anything
running as you: a curious npm postinstall script, a browser extension with file
access, a backup that syncs somewhere you forgot about.

Moving those keys into the Keychain does not magically fix that. A plain Keychain
item is readable by any process running as you once the login keychain is
unlocked, which is all day. What it does fix is the flat file: `cat .env` stops
being a credential dump, and backups stop carrying keys.

Enclave mode is the part that actually raises the bar. The value is encrypted
with a P256 key generated inside the Secure Enclave, and decryption requires a
live human authentication. Until someone touches the sensor, an attacker with
full read access to your disk gets ciphertext.

## Two modes

| | `plain` | `enclave` |
|---|---|---|
| Storage | Keychain generic password | Ciphertext file, key inside the Secure Enclave |
| Read requires | an unlocked login session | live user authentication |
| Works headless | yes, via the System keychain | no, by design |
| Prompt at Hermes startup | never | never, you unlock out of band |
| Value at rest | encrypted by the Keychain | ChaChaPoly, key that cannot be exported |

Pick plain for anything a daemon or cron job needs at boot. Pick enclave for keys
where you would rather the process fail than have them read silently.

## Install

```bash
git clone https://github.com/iacker/hermes-keychain-secretsource \
    ~/.hermes/plugins/keychain-secretsource
```

Enable it in `~/.hermes/config.yaml`. The key is `keychain`, which is the plugin
name from the manifest, not the directory name:

```yaml
plugins:
  enabled:
    - keychain

secrets:
  sources: [keychain]
  keychain:
    enabled: true
```

If you run profiles, the plugin goes in that profile's directory instead, for
example `~/.hermes/profiles/<name>/plugins/`.

The Secure Enclave helper compiles itself the first time you store an enclave
secret. You need Xcode Command Line Tools for that (`xcode-select --install`).

## Storing secrets

```bash
hermes keychain store OPENROUTER_API_KEY            # plain
hermes keychain store GITHUB_TOKEN --enclave        # Secure Enclave
```

Storing registers the secret automatically, so you do not have to hand-edit
`config.yaml` to declare it. The registration lives in a 0600 JSON file under
your profile and is written atomically. Explicit `accounts` and `items` entries
in `config.yaml` still work and still take precedence, so an existing setup keeps
behaving the way it did.

For enclave secrets, authenticate once per session:

```bash
hermes keychain unlock
```

Then check where things stand:

```bash
hermes keychain status
```

## How enclave mode works

```
store --enclave          unlock (once)             fetch (every startup)
     |                        |                          |
     v                        v                          v
P256 public key   ->   one Touch ID prompt   ->   session record   ->   env vars
no prompt              for the whole batch        TTL bounded            silent
```

`keygen` creates the P256 key inside the Secure Enclave, gated on user presence.
Add `--strict-biometry` to bind it to the fingerprints enrolled right now, so
enrolling a new finger invalidates it. The exported key blob is useless on any
other machine.

`encrypt` only needs the public key, so adding a secret never prompts.

`unlock` authenticates once for the whole batch, then caches the plaintexts as
TTL-bounded session records in the login keychain. They are encrypted at rest by
macOS, namespaced per Hermes profile, and expired records delete themselves.

Be honest about what that last step costs you. During the TTL window, those
values are readable by a process running as your unlocked user, which is the same
exposure as plain mode. That is the tradeoff for letting cron jobs and gateway
children start without a prompt. `hermes keychain lock` closes the window early,
and a short `session_ttl_seconds` narrows it.

`fetch()` only ever reads session records. A locked secret produces a warning, or
`AUTH_EXPIRED` with a hint when nothing is readable. It never blocks startup,
because gateway, cron, and subagent processes have to stay non-interactive.

## Headless and daemon setups

launchd jobs at boot have no login session, so use plain mode against the System
keychain:

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

## Config reference

Everything lives under `secrets.keychain`.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `false` | Master switch |
| `service` | `hermes` | Keychain service name for plain items |
| `accounts` | `[]` | Env var names in plain mode, account name equals the variable |
| `items` | `[]` | Per secret: `{env, mode: plain\|enclave, service?, account?, keychain?}` |
| `default_keychain` | `""` | Keychain file for plain reads, empty means the search list |
| `session_ttl_seconds` | `28800` | How long an unlock stays valid, 8 hours |
| `timeout_seconds` | `30` | Wall clock budget for a fetch |

## CLI

```
hermes keychain setup                 walk through first-time setup
hermes keychain store <ENV> [--enclave] [--service S] [--account A]
hermes keychain unlock                one auth, opens every enclave session
hermes keychain lock                  clear sessions now
hermes keychain status                per secret state
hermes keychain delete <ENV>          remove item, ciphertext, session, registration
```

`store` also accepts `--stdin` so a GUI or a script can pipe a value in without
it ever appearing in `ps` output or shell history.

## Desktop app

There is an optional SwiftUI app in [`ui/`](ui/). It shows source and per secret
state, adds and deletes secrets, and runs unlock or lock without a terminal. It
shells out to the same plugin CLI and pipes secret values over stdin, so nothing
sensitive lands in process arguments.

It also has a Sealed Profiles section that reports Chthonios state next to the
Keychain state. The two crypto engines stay separate on purpose. Only the
dashboard is shared, so you can see runtime secrets and sealed profiles in one
window without one system pretending to be the other.

```bash
cd ui
./scripts/test.sh
./scripts/build-app.sh
open "dist/Hermes Keychain.app"
```

The build is ad-hoc signed, which is fine locally. Handing the binary to someone
else means a Developer ID signature and notarization.

## Security model

`fetch()` never raises, never prompts, and never writes to `os.environ`. Hermes
owns precedence and application. This plugin only returns a result.

Subprocess calls pass an argv list with a minimal allowlisted environment and
stdin closed. `/usr/bin/security` therefore cannot prompt, and a locked keychain
fails fast instead of hanging.

The Swift helper is about 200 lines in `helper/main.swift`. You can read the
whole thing in one sitting, which was the point.

Enclave ciphertexts and the key blob live under `$HERMES_HOME/keychain/` at mode
0600. Copying them to another Mac gets you nothing, because the private key
cannot leave this machine's Secure Enclave.

One design note worth recording: biometric Keychain ACLs would have been the
obvious approach, and they do not work here. `SecAccessControl` biometric flags
require the Data Protection keychain, which requires a paid Apple Developer
application-identifier entitlement. An ad-hoc signed open source CLI cannot get
one, and the attempt fails with `errSecMissingEntitlement`. Encrypting against an
enclave key, the same approach age-plugin-se takes, gets the same guarantee
without the entitlement.

## Tests

```bash
HERMES_AGENT_SRC=~/.hermes/hermes-agent \
  uv run --with pytest --with pyyaml --with rich python -m pytest tests/ -v
```

33 tests. They are hermetic, so no real keychain or enclave is touched, and they
include the upstream `SecretSourceConformance` kit.

The Swift side has its own check:

```bash
cd ui && ./scripts/test.sh
```

## License

MIT
