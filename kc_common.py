"""Shared paths, constants and `security` CLI wrappers."""

from __future__ import annotations

import hashlib
import json
import os
import platform
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


def registry_path(home_path: Path) -> Path:
    return state_dir(home_path) / "items.json"


def registered_items(home_path: Path) -> List[dict]:
    try:
        data = json.loads(registry_path(home_path).read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except (OSError, ValueError, TypeError):
        return []


def _write_registered_items(home_path: Path, items: List[dict]) -> None:
    path = registry_path(home_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(items, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.chmod(0o600)
    os.replace(tmp, path)


def register_item(home_path: Path, item: dict) -> None:
    items = [entry for entry in registered_items(home_path)
             if entry.get("env") != item.get("env")]
    items.append(item)
    _write_registered_items(home_path, items)


def unregister_item(home_path: Path, env_name: str) -> None:
    items = [entry for entry in registered_items(home_path)
             if entry.get("env") != env_name]
    _write_registered_items(home_path, items)


def merge_registered_items(cfg: dict, home_path: Path) -> dict:
    merged = dict(cfg) if isinstance(cfg, dict) else {}
    configured, _ = parse_items(merged)
    by_env = {item["env"]: item for item in configured}
    for item in registered_items(home_path):
        if isinstance(item, dict) and valid_env_name(item.get("env")):
            by_env[item["env"]] = item
    merged["items"] = list(by_env.values())
    return merged


def valid_env_name(env_name: object) -> bool:
    import re

    return isinstance(env_name, str) and bool(
        re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", env_name)
    )


def ct_path(home_path: Path, env_name: str) -> Path:
    if not valid_env_name(env_name):
        raise ValueError(f"invalid environment variable name: {env_name!r}")
    return secrets_dir(home_path) / f"{env_name}.ct"


def helper_path() -> Optional[Path]:
    """Return only the plugin-bundled helper, never a PATH substitute."""
    bundled = PLUGIN_DIR / "helper" / HELPER_NAME
    return bundled if bundled.is_file() else None


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
        # Detach from the controlling terminal so `security`'s bare -w prompt
        # can't grab /dev/tty and hang; with no tty it reads the value from
        # stdin, which is the whole point of feeding it there.
        start_new_session=True,
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
    """Upsert one generic password without exposing it in process argv.

    `security` truncates a prompted password at 128 characters and still exits
    0, which silently corrupts anything longer (long OAuth tokens, session
    records). Passing the value via -w/-X instead would put the secret in argv,
    where `ps` can read it — worse. So we write via stdin, then read back and
    verify; a short write is reported as an error rather than stored corrupt.
    """
    # Apple documents `-w <password>` as insecure. Bare `-w` prompts twice;
    # feed both answers through stdin so process listings never reveal value.
    argv = [
        SECURITY_BIN, "add-generic-password", "-U",
        "-s", service, "-a", account, "-w",
    ]
    if keychain:
        argv.append(keychain)
    try:
        encoded = value.encode("utf-8")
        proc = run_cli(argv, stdin_data=encoded + b"\n" + encoded + b"\n")
    except (subprocess.TimeoutExpired, OSError) as exc:
        return f"security invocation failed: {exc}"
    if proc.returncode != 0:
        err = (proc.stderr or b"").decode("utf-8", "replace").strip()
        return err or f"security exited {proc.returncode}"
    # Verify: never let a silent truncation look like success.
    stored, read_err = kc_read(service, account, keychain)
    if stored != value:
        kc_delete(service, account, keychain)
        if read_err:
            return f"write verification failed: {read_err}"
        return (
            f"macOS truncated this value at {len(stored or '')} characters "
            f"(sent {len(value)}); not stored"
        )
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


def session_account(home_path: Path, env_name: str) -> str:
    """Namespace session items by Hermes home to isolate profiles."""
    resolved = str(Path(home_path).expanduser().resolve())
    profile_id = hashlib.sha256(resolved.encode()).hexdigest()[:16]
    return f"{profile_id}:{env_name}"


# `security` silently truncates a prompted password at 128 chars. Session
# payloads (JSON-wrapped value + expiry) routinely exceed that for OAuth
# tokens, so anything larger spills to a 0600 file beside the ciphertexts and
# the Keychain item holds only a pointer. The file lives in the same directory
# that already holds ciphertexts, so it inherits the same 0700 protection.
SESSION_SPILL_PREFIX = "@spill:"
_KC_VALUE_LIMIT = 128


def _spill_path(home_path: Path, env_name: str) -> Path:
    return secrets_dir(home_path) / f"{env_name}.session"


def session_write(home_path: Path, env_name: str, value: str, ttl_seconds: int) -> str:
    payload = json.dumps({"v": value, "exp": int(time.time()) + int(ttl_seconds)})
    account = session_account(home_path, env_name)
    spill = _spill_path(home_path, env_name)
    if len(payload) <= _KC_VALUE_LIMIT:
        spill.unlink(missing_ok=True)
        return kc_write(SESSION_SERVICE, account, payload)
    # Too long for the Keychain: write the payload to disk, point at it.
    spill.parent.mkdir(parents=True, exist_ok=True)
    spill.touch(mode=0o600, exist_ok=True)
    spill.chmod(0o600)
    spill.write_text(payload)
    return kc_write(SESSION_SERVICE, account, SESSION_SPILL_PREFIX + spill.name)


def session_read(home_path: Path, env_name: str) -> Tuple[Optional[str], str]:
    """Returns (value, error). Expired/absent -> (None, reason)."""
    account = session_account(home_path, env_name)
    raw, err = kc_read(SESSION_SERVICE, account)
    if raw is None:
        return None, "no unlock session"
    if raw.startswith(SESSION_SPILL_PREFIX):
        spill = _spill_path(home_path, env_name)
        try:
            raw = spill.read_text()
        except OSError:
            return None, "session file missing"
    try:
        payload = json.loads(raw)
        exp = int(payload["exp"])
        value = payload["v"]
    except (ValueError, KeyError, TypeError):
        return None, "corrupt session record"
    if time.time() >= exp:
        _spill_path(home_path, env_name).unlink(missing_ok=True)
        kc_delete(SESSION_SERVICE, account)
        return None, "unlock session expired"
    if not isinstance(value, str):
        return None, "corrupt session record"
    return value, ""


def session_clear(home_path: Path, env_names: List[str]) -> None:
    for name in env_names:
        _spill_path(home_path, name).unlink(missing_ok=True)
        kc_delete(SESSION_SERVICE, session_account(home_path, name))


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
