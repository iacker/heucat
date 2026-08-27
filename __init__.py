"""Hermes SecretSource plugin: Apple Keychain + Secure Enclave.

Two modes, per-item or per-source:

* ``plain``   — generic passwords read via ``/usr/bin/security``. Works
  headless (System keychain for daemons, login keychain for interactive
  sessions). Parity with the community gist baseline.
* ``enclave`` — secrets stored as ciphertext files that only THIS
  machine's Secure Enclave can decrypt, gated on user presence
  (Touch ID / login password / Apple Watch). Startup never prompts:
  ``hermes keychain unlock`` performs the single interactive
  authentication out-of-band and caches the decrypted values in a
  short-lived session file; ``fetch()`` silently reads that session and
  reports AUTH_EXPIRED (with remediation) when it is absent or stale.

Config (``secrets.keychain`` in config.yaml)::

    secrets:
      sources: [keychain]
      keychain:
        enabled: true
        service: hermes             # default keychain service / SE namespace
        accounts:                   # simple form: plain-mode env vars
          - OPENROUTER_API_KEY
        items:                      # advanced form (all fields optional)
          - env: BRAVE_API_KEY      #   plain, custom account
            account: brave-key
          - env: GITHUB_TOKEN       #   enclave-protected
            mode: enclave
        default_keychain: ""        # plain mode: keychain file override
        session_ttl_seconds: 28800  # enclave unlock validity (8h)

The SecretSource contract (api_version 1) is deliberately narrow:
fetch-only, never raises, never prompts, never writes os.environ.
"""

from __future__ import annotations

try:  # package-style load (tests, pip install)
    from .kc_source import KeychainSource
    from .kc_cli import setup_cli_parser, cli_dispatch
except ImportError:  # flat load (Hermes plugin dir on sys.path)
    from kc_source import KeychainSource  # type: ignore
    from kc_cli import setup_cli_parser, cli_dispatch  # type: ignore

__all__ = ["KeychainSource", "register"]


def register(ctx) -> None:
    """Hermes plugin entry point."""
    source = KeychainSource()
    ctx.register_secret_source(source)
    ctx.register_cli_command(
        "keychain",
        help="Apple Keychain / Secure Enclave secret source",
        setup_fn=setup_cli_parser,
        handler_fn=cli_dispatch,
        description=(
            "Manage the Apple Keychain secret source: store secrets, unlock "
            "the Secure Enclave session, check status."
        ),
    )
