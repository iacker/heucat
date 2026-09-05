"""CLI: `hermes keychain setup|store|unlock|lock|status|delete`."""

from __future__ import annotations

import base64
import getpass
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    from . import kc_common as kc
except ImportError:  # flat load
    import kc_common as kc  # type: ignore


def _home_path() -> Path:
    import os

    return Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))


def _load_cfg() -> dict:
    """Read secrets.keychain from config.yaml (best effort)."""
    try:
        import yaml

        cfg_path = _home_path() / "config.yaml"
        with open(cfg_path, "r", encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh) or {}
        section = (cfg.get("secrets") or {}).get("keychain") or {}
        return section if isinstance(section, dict) else {}
    except Exception:
        return {}


def _effective_cfg() -> dict:
    return kc.merge_registered_items(_load_cfg(), _home_path())


def _helper() -> Optional[Path]:
    return kc.helper_path()


def _ensure_helper_built() -> Tuple[Optional[Path], str]:
    """Locate the helper; build it from bundled source if swiftc exists."""
    helper = _helper()
    if helper:
        return helper, ""
    src = kc.PLUGIN_DIR / "helper" / "main.swift"
    if not src.is_file():
        return None, "helper source missing from plugin"
    import shutil as sh
    import subprocess

    if not sh.which("swiftc"):
        return None, (
            "swiftc not found — install Xcode Command Line Tools "
            "(xcode-select --install) to build the Secure Enclave helper"
        )
    # One build recipe. build.sh embeds Info.plist; without it macOS refuses
    # biometry and unlock silently falls back to the login password.
    try:
        proc = subprocess.run(
            ["/bin/bash", str(src.parent / "build.sh")],
            capture_output=True, text=True, timeout=300,
        )
    except Exception as exc:
        return None, f"helper build failed: {exc}"
    if proc.returncode != 0:
        return None, f"helper build failed: {proc.stderr.strip()[:300]}"
    helper = _helper()
    return (helper, "") if helper else (None, "helper build produced no binary")


def _ensure_key(home: Path) -> Tuple[Optional[str], str]:
    """Load or create the Secure Enclave key blob."""
    blob_path = kc.key_blob_path(home)
    if blob_path.is_file():
        return blob_path.read_text().strip(), ""
    helper, err = _ensure_helper_built()
    if not helper:
        return None, err
    proc = kc.run_cli([helper, "keygen"])
    if proc.returncode != 0:
        return None, (proc.stderr or b"").decode("utf-8", "replace").strip()
    blob = (proc.stdout or b"").decode().strip()
    blob_path.parent.mkdir(parents=True, exist_ok=True)
    blob_path.write_text(blob + "\n")
    blob_path.chmod(0o600)
    return blob, ""


def _biometry_hint(helper) -> None:
    """Warn (once, to stderr) when Secure Enclave is present but no fingerprint
    is enrolled — otherwise macOS silently downgrades to the login password and
    the user never learns Touch ID is one setting away. This is the exact trap
    that makes `unlock` feel broken."""
    proc = kc.run_cli([helper, "check"], timeout=10.0)
    out = (proc.stdout or b"").decode("utf-8", "replace")
    if "secure_enclave=true" in out and "biometry=false" in out:
        print(
            "Touch ID isn't set up on this Mac, so you'll be asked for your "
            "login password instead.\n"
            "  To use your fingerprint: System Settings > Touch ID & Password "
            "> Add Fingerprint, then run this again.",
            file=sys.stderr,
        )


def _pubkey(key_blob: str) -> Tuple[Optional[str], str]:
    helper, err = _ensure_helper_built()
    if not helper:
        return None, err
    proc = kc.run_cli([helper, "pubkey", key_blob])
    if proc.returncode != 0:
        return None, (proc.stderr or b"").decode("utf-8", "replace").strip()
    return (proc.stdout or b"").decode().strip(), ""


# -- commands -----------------------------------------------------------------


def _write_enclave(home: Path, env_name: str, value: str) -> Tuple[int, str]:
    """Encrypt value to the Secure Enclave key and register it. Shared by
    `store --enclave` and `migrate`. Returns (rc, message)."""
    key_blob, err = _ensure_key(home)
    if not key_blob:
        return 1, f"enclave key unavailable: {err}"
    pub, err = _pubkey(key_blob)
    if not pub:
        return 1, f"pubkey failed: {err}"
    helper = _helper()
    proc = kc.run_cli([helper, "encrypt", pub], stdin_data=value.encode())
    if proc.returncode != 0:
        return 1, "encrypt failed: " + (proc.stderr or b"").decode("utf-8", "replace").strip()
    ct = (proc.stdout or b"").decode().strip()
    dest = kc.ct_path(home, env_name)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(ct + "\n")
    dest.chmod(0o600)
    kc.register_item(home, {"env": env_name, "mode": "enclave"})
    return 0, f"stored {env_name} (enclave-encrypted, {dest})"


def cmd_store(args) -> int:
    env_name = args.env_name
    if not kc.valid_env_name(env_name):
        print(f"invalid environment variable name: {env_name!r}", file=sys.stderr)
        return 2
    requested_mode = "enclave" if args.enclave else "plain"
    home = _home_path()
    items, _ = kc.parse_items(_effective_cfg())
    existing = next((item for item in items if item["env"] == env_name), None)
    if existing and existing["mode"] != requested_mode:
        print(
            f"{env_name} is {existing['mode']}-mode; use `hermes keychain migrate {env_name}` "
            "to change protection",
            file=sys.stderr,
        )
        return 2
    mode = existing["mode"] if existing else requested_mode
    if existing and mode == "plain":
        requested_location = {
            "service": args.service,
            "account": args.account,
        }
        for field, requested in requested_location.items():
            if requested and requested != existing[field]:
                print(
                    f"cannot change {field} while updating {env_name}; delete and store it again",
                    file=sys.stderr,
                )
                return 2

    value = sys.stdin.read().rstrip("\n") if args.stdin else getpass.getpass(
        f"Value for {env_name} (hidden): "
    )
    if not value:
        print("empty value, aborting", file=sys.stderr)
        return 1

    if mode == "plain":
        service = args.service or (existing or {}).get("service") or kc.DEFAULT_SERVICE
        account = args.account or (existing or {}).get("account") or env_name
        keychain = (existing or {}).get("keychain", "")
        err = kc.kc_write(service, account, value, keychain)
        if err:
            print(f"keychain write failed: {err}", file=sys.stderr)
            return 1
        kc.register_item(home, {
            "env": env_name, "mode": mode,
            "service": service, "account": account, "keychain": keychain,
        })
        print(f"stored {env_name} (plain, service={service})")
    else:
        rc, msg = _write_enclave(home, env_name, value)
        if rc != 0:
            print(msg, file=sys.stderr)
            return rc
        print(msg)

    print("Registered automatically; new Hermes processes can load it at startup.")
    return 0


def cmd_unlock(args) -> int:
    home = _home_path()
    cfg = _effective_cfg()
    items, warnings = kc.parse_items(cfg)
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)

    enclave_items = [i for i in items if i["mode"] == "enclave"]
    if not enclave_items:
        print("no enclave-mode secrets configured — nothing to unlock")
        return 0

    missing = [i["env"] for i in enclave_items
               if not kc.ct_path(home, i["env"]).is_file()]
    if missing:
        print(f"no ciphertext for: {', '.join(missing)} — "
              f"store them first with `hermes keychain store <ENV> --enclave`",
              file=sys.stderr)
    targets = [i["env"] for i in enclave_items
               if kc.ct_path(home, i["env"]).is_file()]
    if not targets:
        return 1

    key_blob, err = _ensure_key(home)
    if not key_blob:
        print(f"enclave key unavailable: {err}", file=sys.stderr)
        return 1
    helper, err = _ensure_helper_built()
    if not helper:
        print(err, file=sys.stderr)
        return 1

    cts = [kc.ct_path(home, name).read_text().strip() for name in targets]
    _biometry_hint(helper)
    print(f"Authenticating to unlock {len(targets)} secret(s)…")
    proc = kc.run_cli([helper, "decrypt", key_blob, *cts], timeout=120.0)
    if proc.returncode == 5:
        print("cancelled", file=sys.stderr)
        return 1
    if proc.returncode != 0:
        print("decrypt failed:",
              (proc.stderr or b"").decode("utf-8", "replace").strip(),
              file=sys.stderr)
        return 1

    try:
        values: List[str] = json.loads((proc.stdout or b"").decode())
        if not isinstance(values, list) or len(values) != len(targets):
            raise ValueError("helper returned the wrong number of plaintexts")
        plaintexts = [base64.b64decode(v, validate=True).decode("utf-8") for v in values]
    except (ValueError, TypeError, UnicodeDecodeError) as exc:
        print(f"helper output unreadable: {exc}", file=sys.stderr)
        return 1

    ttl = kc.session_ttl(cfg)
    for env_name, value in zip(targets, plaintexts):
        err = kc.session_write(home, env_name, value, ttl)
        if err:
            kc.session_clear(home, targets)
            print(f"session write failed for {env_name}: {err}", file=sys.stderr)
            return 1
    hours = ttl / 3600
    print(f"Unlocked {len(targets)} secret(s) for {hours:.1f}h: "
          f"{', '.join(targets)}")
    print("New Hermes processes will now see them at startup.")
    return 0


def cmd_lock(args) -> int:
    cfg = _effective_cfg()
    items, _ = kc.parse_items(cfg)
    targets = [i["env"] for i in items if i["mode"] == "enclave"]
    try:
        kc.session_clear(_home_path(), targets)
    except (RuntimeError, ValueError, OSError) as exc:
        print(f"lock incomplete: {exc}", file=sys.stderr)
        return 1
    print(f"cleared {len(targets)} unlock session(s)")
    return 0


def _human_delay(seconds: int) -> str:
    """`27000` -> `7h30m`, `900` -> `15m`, `40` -> `<1m`."""
    h, m = divmod(seconds // 60, 60)
    if h:
        return f"{h}h{m:02d}m"
    return f"{m}m" if m else "<1m"


def cmd_status(args) -> int:
    home = _home_path()
    raw_cfg = _load_cfg()
    cfg = _effective_cfg()
    enabled = bool(raw_cfg.get("enabled"))
    items, warnings = kc.parse_items(cfg)
    helper = _helper()

    print(f"source enabled : {enabled}")
    print(f"helper binary  : {helper or 'not built (auto-builds on first store --enclave)'}")
    if helper:
        chk = (kc.run_cli([helper, "check"], timeout=10.0).stdout or b"").decode("utf-8", "replace")
        if "secure_enclave=true" in chk:
            biometry = "Touch ID ready" if "biometry=true" in chk \
                else "no fingerprint enrolled — falls back to login password"
            print(f"biometry       : {biometry}")
    print(f"enclave key    : {'present' if kc.key_blob_path(home).is_file() else 'none yet'}")
    print(f"configured     : {len(items)} secret(s)")
    for item in items:
        if item["mode"] == "plain":
            value, err = kc.kc_read(item["service"], item["account"], item["keychain"])
            state = "readable" if value else f"UNREADABLE ({err[:60]})"
        else:
            if not kc.ct_path(home, item["env"]).is_file():
                state = "NO CIPHERTEXT — run `hermes keychain store … --enclave`"
            else:
                value, err = kc.session_read(home, item["env"])
                if value:
                    # ponytail: a second keychain read on the status path only,
                    # never on fetch. Fold it into session_read if status ever
                    # gets slow with many secrets.
                    left = kc.session_expires_in(home, item["env"])
                    state = f"unlocked ({_human_delay(left)} left)" if left else "unlocked"
                else:
                    state = f"locked ({err})"
        print(f"  {item['env']:<28} {item['mode']:<8} {state}")
    for w in warnings:
        print(f"warning: {w}")
    return 0


def cmd_delete(args) -> int:
    home = _home_path()
    env_name = args.env_name
    if not kc.valid_env_name(env_name):
        print(f"invalid environment variable name: {env_name!r}", file=sys.stderr)
        return 2
    items, _ = kc.parse_items(_effective_cfg())
    item = next((candidate for candidate in items if candidate["env"] == env_name), None)
    if item is None and not (args.service or args.account):
        print(f"{env_name} is not registered", file=sys.stderr)
        return 1
    if item and item["mode"] == "plain":
        service = args.service or item["service"]
        account = args.account or item["account"]
        err = kc.kc_delete(service, account, item.get("keychain", ""))
        if err:
            print(f"keychain delete failed: {err}", file=sys.stderr)
            return 1
    elif not item and (args.service or args.account):
        err = kc.kc_delete(args.service or kc.DEFAULT_SERVICE, args.account or env_name)
        if err:
            print(f"keychain delete failed: {err}", file=sys.stderr)
            return 1
    ct = kc.ct_path(home, env_name)
    if ct.is_file():
        ct.unlink()
    kc.session_clear(home, [env_name])
    kc.unregister_item(home, env_name)
    print(f"deleted {env_name} (keychain item, ciphertext, session, registration)")
    return 0


def cmd_migrate(args) -> int:
    """Move a plain secret into the Secure Enclave: read plaintext, re-encrypt,
    delete the old Keychain item. The value never leaves this process."""
    home = _home_path()
    env_name = args.env_name
    if not kc.valid_env_name(env_name):
        print(f"invalid environment variable name: {env_name!r}", file=sys.stderr)
        return 2
    items, _ = kc.parse_items(_effective_cfg())
    item = next((i for i in items if i["env"] == env_name), None)
    if item is None:
        print(f"{env_name} is not registered", file=sys.stderr)
        return 1
    if item["mode"] == "enclave":
        print(f"{env_name} is already enclave-mode")
        return 0
    value, err = kc.kc_read(item["service"], item["account"], item.get("keychain", ""))
    if not value:
        print(f"cannot read plain value for {env_name}: {err}", file=sys.stderr)
        return 1
    rc, msg = _write_enclave(home, env_name, value)
    if rc != 0:
        print(msg, file=sys.stderr)
        return rc
    kc.kc_delete(item["service"], item["account"], item.get("keychain", ""))
    print(f"migrated {env_name} to enclave (old plain Keychain item removed)")
    return 0


def _read_value(home: Path, item: dict) -> Tuple[Optional[str], str]:
    """Read a secret's plaintext for an internal probe. Plain reads from the
    Keychain; enclave reads the unlock session (fails if locked)."""
    if item["mode"] == "plain":
        return kc.kc_read(item["service"], item["account"], item.get("keychain", ""))
    return kc.session_read(home, item["env"])


# env-name substring -> (authenticated endpoint, header builder).
# Keep only providers whose endpoint actually rejects missing credentials.
_PROBES: Dict[str, tuple] = {
    "MISTRAL": ("https://api.mistral.ai/v1/models", lambda v: {"Authorization": f"Bearer {v}"}),
    "OPENROUTER": ("https://openrouter.ai/api/v1/credits", lambda v: {"Authorization": f"Bearer {v}"}),
    "OPENAI": ("https://api.openai.com/v1/models", lambda v: {"Authorization": f"Bearer {v}"}),
}


def cmd_test(args) -> int:
    """Ping the provider for a secret and report ok/dead. Never prints the value."""
    import urllib.error
    import urllib.request

    home = _home_path()
    env_name = args.env_name
    items, _ = kc.parse_items(_effective_cfg())
    item = next((i for i in items if i["env"] == env_name), None)
    if item is None:
        print(f"{env_name} is not registered", file=sys.stderr)
        return 2
    probe = next((p for key, p in _PROBES.items() if key in env_name), None)
    if probe is None:
        print(f"unknown: no known endpoint for {env_name}")
        return 3
    value, err = _read_value(home, item)
    if not value:
        print(f"unreadable: {err or 'locked — unlock first'}", file=sys.stderr)
        return 1
    url, headers = probe[0], probe[1](value)
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            code = resp.status
    except urllib.error.HTTPError as exc:
        code = exc.code
    except Exception as exc:
        print(f"dead: {type(exc).__name__}", file=sys.stderr)
        return 1
    if 200 <= code < 300:
        print(f"ok: {env_name} authenticated (HTTP {code})")
        return 0
    if code == 429:
        print(f"unknown: provider rate limited the check (HTTP {code})")
        return 3
    print(f"dead: HTTP {code} (authentication not accepted)", file=sys.stderr)
    return 1


def cmd_log(args) -> int:
    """Show the last fetches: when, which process, what was served or refused."""
    import time as _time

    path = kc.access_log_path(_home_path())
    if not path.is_file():
        print("no access recorded yet")
        return 0
    lines = path.read_text(encoding="utf-8").splitlines()[-args.n:]
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        when = _time.strftime("%Y-%m-%d %H:%M:%S", _time.localtime(e.get("ts", 0)))
        parts = [f"served {', '.join(e['served'])}" if e.get("served") else "served nothing"]
        if e.get("locked"):
            parts.append(f"locked {', '.join(e['locked'])}")
        if e.get("failed"):
            parts.append(f"failed {', '.join(e['failed'])}")
        print(f"{when}  pid {e.get('pid')}  {'; '.join(parts)}")
    return 0


def cmd_export(args) -> int:
    """Emit readable secrets as shell lines so any harness (not just Hermes) can
    load them: `eval "$(hermes keychain export)"`. Values go to stdout;
    diagnostics to stderr so stdout stays sourceable. Never prints a value that
    could not be read."""
    home = _home_path()
    items, warnings = kc.parse_items(_effective_cfg())
    for w in warnings:
        print(w, file=sys.stderr)
    if not items:
        print("no secrets registered", file=sys.stderr)
        return 1
    served, locked = [], []
    for item in items:
        value, err = _read_value(home, item)
        if not value:
            locked.append(item["env"])
            print(f"{item['env']}: {err or 'locked — run hermes keychain unlock'}",
                  file=sys.stderr)
            continue
        # Single-quote and escape embedded quotes: 'it'\''s' is the POSIX idiom.
        quoted = "'" + value.replace("'", "'\\''") + "'"
        prefix = "" if args.dotenv else "export "
        print(f"{prefix}{item['env']}={quoted}")
        served.append(item["env"])
    kc.log_access(home, served=served, locked=locked, failed=[])
    return 0 if served and not locked else 1


def cmd_setup(args) -> int:
    print("Apple Keychain / Secure Enclave secret source — setup\n")
    print("1. Store a secret:")
    print("     hermes keychain store OPENROUTER_API_KEY            # plain")
    print("     hermes keychain store GITHUB_TOKEN --enclave        # SE-gated")
    print("2. Secrets are registered automatically in the active Hermes profile.")
    print("3. For enclave secrets, open a session (one Touch ID / password):")
    print("     hermes keychain unlock")
    print("4. Verify: hermes keychain status")
    return 0


# -- argparse wiring ----------------------------------------------------------


def setup_cli_parser(parser) -> None:
    sub = parser.add_subparsers(dest="kc_cmd")

    p = sub.add_parser("setup", help="show setup instructions")
    p.set_defaults(kc_fn=cmd_setup)

    p = sub.add_parser("store", help="store a secret (plain or --enclave)")
    p.add_argument("env_name")

    p.add_argument("--enclave", action="store_true",
                   help="encrypt to the Secure Enclave key (auth-gated)")
    p.add_argument("--service", default=None)
    p.add_argument("--account", default=None)
    p.add_argument("--stdin", action="store_true", help="read value from stdin")
    p.set_defaults(kc_fn=cmd_store)

    p = sub.add_parser("unlock", help="authenticate once, open the session")
    p.set_defaults(kc_fn=cmd_unlock)

    p = sub.add_parser("lock", help="clear unlock sessions now")
    p.set_defaults(kc_fn=cmd_lock)

    p = sub.add_parser("status", help="show per-secret state")
    p.set_defaults(kc_fn=cmd_status)

    p = sub.add_parser("delete", help="remove a secret everywhere")
    p.add_argument("env_name")
    p.add_argument("--service", default=None)
    p.add_argument("--account", default=None)
    p.set_defaults(kc_fn=cmd_delete)

    p = sub.add_parser("migrate", help="move a plain secret into the Secure Enclave")
    p.add_argument("env_name")
    p.set_defaults(kc_fn=cmd_migrate)

    p = sub.add_parser("test", help="ping the provider to check a key is live")
    p.add_argument("env_name")
    p.set_defaults(kc_fn=cmd_test)

    p = sub.add_parser("log", help="show recent secret accesses")
    p.add_argument("-n", type=int, default=20, help="lines to show (default 20)")
    p.set_defaults(kc_fn=cmd_log)

    p = sub.add_parser("export",
                       help="emit KEY=value lines for any harness: "
                            "eval \"$(hermes keychain export)\"")
    p.add_argument("--dotenv", action="store_true",
                   help="drop the 'export ' prefix (plain .env lines)")
    p.set_defaults(kc_fn=cmd_export)


def cli_dispatch(args) -> int:
    fn = getattr(args, "kc_fn", None)
    if fn is None:
        return cmd_setup(args)
    return fn(args)
