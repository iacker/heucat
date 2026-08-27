"""Shared paths, constants and `security` CLI wrappers."""

from __future__ import annotations

import json
import platform
import shutil
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

SECURITY_BIN = "/usr/bin/security"
DEFAULT_SERVICE = "hermes"
SESSION_SERVICE = "hermes-keychain-session"
DEFAULT_SESSION_TTL = 8 * 3600  # 8h
HELPER_NAME = "hermes-keychain-helper"

PLUGIN_DIR = Path(__file__).resolve().parent


def is_macos() -> bool:
    return platform.system() == "Darwin"


def state_dir(home_path: Path) -> Path:
    return Path(home_path) / "keychain"


def key_blob_path(home_path: Path) -> Path:
    return state_dir(home_path) / "enclave-key.b64"


def secrets_dir(home_path: Path) -> Path:
    return state_dir(home_path) / "secrets"


def ct_path(home_path: Path, env_name: str) -> Path:
    return secrets_dir(home_path) / f"{env_name}.ct"


def helper_path() -> Optional[Path]:
    """Locate the signed Swift helper (bundled build, then PATH)."""
    bundled = PLUGIN_DIR / "helper" / HELPER_NAME
    if bundled.is_file():
        return bundled
    found = shutil.which(HELPER_NAME)
    return Path(found) if found else None


def run_cli(argv, *, timeout: float = 30.0, stdin_data: Optional[bytes] = None):
    """argv-list subprocess with a minimal env. Never shell=True.

    Mirrors agent.secret_sources.base.run_secret_cli (which we cannot
    import unconditionally: the CLI paths also run outside a hermes
    process, e.g. in the plugin's own test suite).
    """
    import os

    env = {}
    for key in ("PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"):
        val = os.environ.get(key)
        if val is not None:
            env[key] = val
    env.setdefault("NO_COLOR", "1")
    return subprocess.run(
        [str(a) for a in argv],
        env=env,
        capture_output=True,
        timeout=timeout,
        input=stdin_data,
        stdin=None if stdin_data is not None else subprocess.DEVNULL,
    )


# -- generic-password helpers (plain mode + session store) -------------------


def kc_read(service: str, account: str, keychain: str = "") -> Tuple[Optional[str], str]:
    """Read one generic password. Returns (value, error). Never prompts:
    -w prints the raw value; a locked/denied item fails fast because
    stdin is closed."""
    argv = [SECURITY_BIN, "find-generic-password", "-s", service, "-a", account, "-w"]
    if keychain:
        argv.append(keychain)
    try:
        proc = run_cli(argv)
    except (subprocess.TimeoutExpired, OSError) as exc:
        return None, f"security invocation failed: {exc}"
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", "replace").strip()
        return None, err or f"security exited {proc.returncode}"
    # -w emits the value followed by a newline; strip exactly one.
    out = (proc.stdout or b"").decode("utf-8", "replace")
    return out[:-1] if out.endswith("\n") else out, ""


def kc_write(service: str, account: str, value: str, keychain: str = "") -> str:
    """Upsert one generic password. Returns error string ('' on success)."""
    argv = [
        SECURITY_BIN, "add-generic-password", "-U",
        "-s", service, "-a", account, "-w", value,
    ]
    if keychain:
        argv.append(keychain)
    try:
        proc = run_cli(argv)
    except (subprocess.TimeoutExpired, OSError) as exc:
        return f"security invocation failed: {exc}"
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", "replace").strip()
        return err or f"security exited {proc.returncode}"
    return ""


def kc_delete(service: str, account: str, keychain: str = "") -> str:
    argv = [SECURITY_BIN, "delete-generic-password", "-s", service, "-a", account]
    if keychain:
        argv.append(keychain)
    try:
        proc = run_cli(argv)
    except (subprocess.TimeoutExpired, OSError) as exc:
        return f"security invocation failed: {exc}"
    if proc.returncode not in (0, 44):  # 44 = errSecItemNotFound path
        err = (proc.stderr or b"").decode("utf-8", "replace").strip()
        if "could not be found" not in err:
            return err or f"security exited {proc.returncode}"
    return ""


# -- unlock-session records ---------------------------------------------------
#
# A session record is one login-keychain item under SESSION_SERVICE whose
# value is JSON {"v": <secret>, "exp": <unix-ts>}. Plaintext never touches
# disk: the login keychain is encrypted at rest by macOS and only readable
# inside this user's login session.


def session_write(env_name: str, value: str, ttl_seconds: int) -> str:
    payload = json.dumps({"v": value, "exp": int(time.time()) + int(ttl_seconds)})
    return kc_write(SESSION_SERVICE, env_name, payload)


def session_read(env_name: str) -> Tuple[Optional[str], str]:
    """Returns (value, error). Expired/absent -> (None, reason)."""
    raw, err = kc_read(SESSION_SERVICE, env_name)
    if raw is None:
        return None, "no unlock session"
    try:
        payload = json.loads(raw)
        exp = int(payload["exp"])
        value = payload["v"]
    except (ValueError, KeyError, TypeError):
        return None, "corrupt session record"
    if time.time() >= exp:
        kc_delete(SESSION_SERVICE, env_name)
        return None, "unlock session expired"
    if not isinstance(value, str):
        return None, "corrupt session record"
    return value, ""


def session_clear(env_names: List[str]) -> None:
    for name in env_names:
        kc_delete(SESSION_SERVICE, name)


# -- config parsing -----------------------------------------------------------


def parse_items(cfg: dict) -> Tuple[List[Dict[str, str]], List[str]]:
    """Normalize `accounts` + `items` into per-secret dicts.

    Each item: {env, mode, service, account, keychain}.
    Returns (items, warnings). Defensive: cfg may be malformed.
    """
    import re

    env_re = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
    warnings: List[str] = []
    items: List[Dict[str, str]] = []

    if not isinstance(cfg, dict):
        return [], ["keychain config section is not a mapping"]

    service = cfg.get("service")
    service = service.strip() if isinstance(service, str) and service.strip() else DEFAULT_SERVICE
    default_keychain = cfg.get("default_keychain")
    default_keychain = default_keychain.strip() if isinstance(default_keychain, str) else ""

    accounts = cfg.get("accounts") or []
    if not isinstance(accounts, list):
        warnings.append("ignoring keychain.accounts: expected a list")
        accounts = []
    for account in accounts:
        if not isinstance(account, str) or not env_re.match(account):
            warnings.append(f"skipping account {account!r}: not a valid env var name")
            continue
        items.append({
            "env": account, "mode": "plain", "service": service,
            "account": account, "keychain": default_keychain,
        })

    raw_items = cfg.get("items") or []
    if not isinstance(raw_items, list):
        warnings.append("ignoring keychain.items: expected a list")
        raw_items = []
    for raw in raw_items:
        if not isinstance(raw, dict):
            warnings.append(f"skipping item {raw!r}: expected a mapping")
            continue
        env_name = raw.get("env")
        if not isinstance(env_name, str) or not env_re.match(env_name):
            warnings.append(f"skipping item {raw!r}: missing valid env name")
            continue
        mode = raw.get("mode", "plain")
        if mode not in ("plain", "enclave"):
            warnings.append(f"skipping item {env_name}: unknown mode {mode!r}")
            continue
        item_service = raw.get("service")
        item_service = (
            item_service.strip()
            if isinstance(item_service, str) and item_service.strip() else service
        )
        account = raw.get("account")
        account = (
            account.strip()
            if isinstance(account, str) and account.strip() else env_name
        )
        item_keychain = default_keychain
        if isinstance(raw.get("keychain"), str) and raw["keychain"].strip():
            item_keychain = raw["keychain"].strip()
        items.append({
            "env": env_name, "mode": mode, "service": item_service,
            "account": account, "keychain": item_keychain,
        })

    seen: set = set()
    deduped: List[Dict[str, str]] = []
    for item in items:
        if item["env"] in seen:
            warnings.append(f"duplicate keychain target {item['env']}; keeping the first")
            continue
        seen.add(item["env"])
        deduped.append(item)
    return deduped, warnings


def session_ttl(cfg: dict) -> int:
    try:
        ttl = int((cfg or {}).get("session_ttl_seconds", DEFAULT_SESSION_TTL))
    except (TypeError, ValueError):
        return DEFAULT_SESSION_TTL
    return ttl if ttl > 0 else DEFAULT_SESSION_TTL
