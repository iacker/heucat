"""KeychainSource — the SecretSource implementation."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, FrozenSet, Optional

from agent.secret_sources.base import (
    ErrorKind,
    FetchResult,
    SecretSource,
)

try:
    from . import kc_common as kc
except ImportError:  # flat load
    import kc_common as kc  # type: ignore


class KeychainSource(SecretSource):
    """Apple Keychain (plain) + Secure Enclave (enclave) secret source.

    Contract compliance:
    - fetch() never raises, never prompts, never writes os.environ.
    - plain items read via /usr/bin/security with stdin closed (a locked
      keychain fails fast instead of prompting).
    - enclave items read the out-of-band unlock session; absent/expired
      sessions surface AUTH_EXPIRED with a remediation hint, they never
      block startup.
    """

    name = "keychain"
    label = "Apple Keychain / Secure Enclave"
    shape = "bulk"

    def fetch(self, cfg: dict, home_path: Path) -> FetchResult:
        result = FetchResult()
        try:
            return self._fetch(cfg, home_path, result)
        except Exception as exc:  # noqa: BLE001 — contract: never raise
            result.secrets = {}
            result.error = f"unexpected error: {exc}"
            result.error_kind = ErrorKind.INTERNAL
            return result

    def _fetch(self, cfg: dict, home_path: Path, result: FetchResult) -> FetchResult:
        if not kc.is_macos():
            result.error = "Apple Keychain source requires macOS"
            result.error_kind = ErrorKind.NOT_CONFIGURED
            return result
        if not os.path.exists(kc.SECURITY_BIN):
            result.error = f"{kc.SECURITY_BIN} not found"
            result.error_kind = ErrorKind.BINARY_MISSING
            return result

        effective_cfg = kc.merge_registered_items(
            cfg if isinstance(cfg, dict) else {}, home_path
        )
        items, warnings = kc.parse_items(effective_cfg)
        result.warnings.extend(warnings)
        if not items:
            result.error = (
                "no secrets configured — add env var names under "
                "secrets.keychain.accounts or secrets.keychain.items"
            )
            result.error_kind = ErrorKind.NOT_CONFIGURED
            return result

        secrets: Dict[str, str] = {}
        expired: list = []
        failed: list = []

        for item in items:
            if item["mode"] == "plain":
                value, err = kc.kc_read(
                    item["service"], item["account"], item["keychain"]
                )
                if value is None:
                    failed.append((item["env"], err))
                elif value == "":
                    result.warnings.append(f"{item['env']}: empty value in keychain")
                else:
                    secrets[item["env"]] = value
            else:  # enclave
                value, err = kc.session_read(home_path, item["env"])
                if value is None:
                    expired.append((item["env"], err))
                else:
                    secrets[item["env"]] = value

        result.secrets = secrets
        result.binary_path = Path(kc.SECURITY_BIN)
        kc.log_access(home_path, served=sorted(secrets),
                      locked=[e for e, _ in expired], failed=[e for e, _ in failed])

        for env_name, err in failed:
            result.warnings.append(f"{env_name}: {self._short(err)}")

        if expired and not secrets and not failed:
            # Everything asked of us needs an unlock — one clean error.
            result.error = (
                f"{len(expired)} enclave secret(s) locked "
                f"({expired[0][1]})"
            )
            result.error_kind = ErrorKind.AUTH_EXPIRED
        elif expired:
            for env_name, err in expired:
                result.warnings.append(
                    f"{env_name}: {err} — run `hermes keychain unlock`"
                )
        elif failed and not secrets:
            result.error = f"no secret could be read ({self._short(failed[0][1])})"
            result.error_kind = ErrorKind.AUTH_FAILED
        return result

    @staticmethod
    def _short(text: str, limit: int = 160) -> str:
        return " ".join((text or "").split())[:limit]

    # -- optional hooks -----------------------------------------------------

    def protected_env_vars(self, cfg: dict) -> FrozenSet[str]:
        return frozenset()

    def config_schema(self) -> dict:
        return {
            "enabled": {"description": "Master switch", "default": False},
            "service": {
                "description": "Keychain service / namespace for stored items",
                "default": kc.DEFAULT_SERVICE,
            },
            "accounts": {
                "description": "Env var names to read in plain mode "
                               "(account name == env var name)",
                "default": [],
            },
            "items": {
                "description": "Per-secret entries: {env, mode: plain|enclave, "
                               "service?, account?, keychain?}",
                "default": [],
            },
            "default_keychain": {
                "description": "Keychain file for plain reads (empty = search "
                               "list; /Library/Keychains/System.keychain for "
                               "headless daemons)",
                "default": "",
            },
            "session_ttl_seconds": {
                "description": "Enclave unlock session validity",
                "default": kc.DEFAULT_SESSION_TTL,
            },
            "timeout_seconds": {
                "description": "Fetch wall-clock budget",
                "default": 30,
            },
        }

    def remediation(self, kind: Optional[ErrorKind], cfg: dict) -> str:
        if kind == ErrorKind.AUTH_EXPIRED:
            return "Run `hermes keychain unlock` to open a new session."
        if kind == ErrorKind.AUTH_FAILED:
            return (
                "Check `hermes keychain status`; store missing secrets with "
                "`hermes keychain store <ENV_NAME>`."
            )
        if kind == ErrorKind.NOT_CONFIGURED:
            return "Run `hermes keychain setup` to configure the source."
        if kind == ErrorKind.BINARY_MISSING:
            return "This source needs macOS with /usr/bin/security available."
        return super().remediation(kind, cfg)
