<div align="center">

# HEUCAT

**H**ardware **E**nclave **C**redential **A**uthentication **T**ool

Serve [Hermes Agent](https://github.com/NousResearch/hermes-agent) API keys from the macOS
Keychain instead of a plaintext `.env`. Enclave secrets sit behind Touch ID, encrypted with a
key that never leaves the Secure Enclave.

[![macOS](https://img.shields.io/badge/macOS-14%2B-1B1D24?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Secure Enclave](https://img.shields.io/badge/Secure%20Enclave-Apple%20silicon-1F8B68?style=flat-square)](https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web)
[![Tests](https://img.shields.io/badge/tests-56%20passing-1F8B68?style=flat-square)](#tests)
[![License](https://img.shields.io/badge/license-MIT-676B76?style=flat-square)](#license)

**[Full documentation →](https://iacker.github.io/heucat/)**

</div>

---

## Install

Needs Apple silicon, [Hermes Agent](https://github.com/NousResearch/hermes-agent), and Xcode
Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/iacker/heucat && cd heucat
./install.sh                              # link plugin, build enclave helper, print config
hermes keychain store OPENROUTER_API_KEY
```

Add `--app` to `install.sh` for the menu-bar app, or grab the
[prebuilt release](https://github.com/iacker/heucat/releases/latest). It is ad-hoc signed, so
macOS quarantines it once:

```bash
unzip HEUCAT-Keychain.zip -d /Applications
xattr -dr com.apple.quarantine "/Applications/HEUCAT Keychain.app"
```

## Two modes

| | `plain` | `enclave` |
|---|---|---|
| Storage | Keychain generic password | Ciphertext file, key inside the Secure Enclave |
| Read requires | an unlocked login session | live user authentication (Touch ID) |
| Works headless | yes, via the System keychain | no, by design |
| Prompt at Hermes startup | never | never — you `unlock` out of band |

Plain for anything a daemon or cron job needs at boot. Enclave for keys where you would rather
the process fail than have them read silently.

## CLI

```
hermes keychain store <ENV> [--enclave]   store a secret, registers it automatically
hermes keychain unlock                    one Touch ID, opens every enclave session
hermes keychain lock                      clear sessions now
hermes keychain status                    per-secret state
hermes keychain delete <ENV>              remove item, ciphertext, session, registration
hermes keychain export [--dotenv]         emit KEY=value lines for any harness
```

Values reach the CLI over stdin, never `argv`, so nothing lands in `ps` or shell history.
`export` bridges to non-Hermes tools: `eval "$(hermes keychain export)"`.

## Security model

| Threat | `.env` | `plain` | `enclave` |
|---|---|---|---|
| Disk read (backup, sync, stolen Mac) | **Plaintext. Game over.** | Encrypted, needs your login session | **Ciphertext only, useless off this Mac** |
| Process running as you, *before* unlock | Readable | Readable | **Unreadable** |
| Same process, *after* `unlock`, within TTL | Readable | Readable | **Readable — this is the tradeoff** |

The last row is the honest part: once you unlock, a process running as you can read those values
for the TTL. That is the price of never prompting a cron job. `lock` closes it early; a short
`session_ttl_seconds` narrows it.

`fetch()` never raises, prompts, or writes to `os.environ` — Hermes owns precedence. Full details,
config reference, headless setup, and the desktop app are on the
**[documentation site](https://iacker.github.io/heucat/)**.

## Tests

```bash
HERMES_AGENT_SRC=~/.hermes/hermes-agent PYTHONPATH=~/.hermes/hermes-agent \
  uv run --with pytest --with pyyaml --with rich python -m pytest tests/ -v
cd ui && ./scripts/test.sh   # Swift status parser + FR/EN and exit-code drift guards
```

56 tests, mostly hermetic. `tests/test_long_values.py` touches a scratch Keychain item because the
bug it pins only reproduces against the real `security` binary.

## License

MIT
