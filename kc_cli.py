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

    swiftc = sh.which("swiftc")
    if not swiftc:
        return None, (
            "swiftc not found — install Xcode Command Line Tools "
            "(xcode-select --install) to build the Secure Enclave helper"
        )
    out = src.parent / kc.HELPER_NAME
    try:
        proc = subprocess.run(
            [swiftc, "-O", "-o", str(out), str(src)],
            capture_output=True, text=True, timeout=300,
        )
        if proc.returncode != 0:
            return None, f"helper build failed: {proc.stderr.strip()[:300]}"
        signed = subprocess.run(
            ["/usr/bin/codesign", "-s", "-", "-f",
             "--identifier", "com.hermes.keychain-helper", str(out)],
            capture_output=True, text=True, timeout=60,
        )
        if signed.returncode != 0:
            out.unlink(missing_ok=True)
            return None, f"helper signing failed: {signed.stderr.strip()[:300]}"
    except Exception as exc:
        return None, f"helper build failed: {exc}"
    return out, ""


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


def cmd_store(args) -> int:
    env_name = args.env_name
    if not kc.valid_env_name(env_name):
        print(f"invalid environment variable name: {env_name!r}", file=sys.stderr)
        return 2
    mode = "enclave" if args.enclave else "plain"
    home = _home_path()

    value = sys.stdin.read().rstrip("\n") if args.stdin else getpass.getpass(
        f"Value for {env_name} (hidden): "
    )
    if not value:
        print("empty value, aborting", file=sys.stderr)
        return 1

    if mode == "plain":
        service = args.service or kc.DEFAULT_SERVICE
        account = args.account or env_name
        err = kc.kc_write(service, account, value)
        if err:
            print(f"keychain write failed: {err}", file=sys.stderr)
            return 1
        kc.register_item(home, {
            "env": env_name, "mode": mode,
            "service": service, "account": account,
        })
        print(f"stored {env_name} (plain, service={service})")
    else:
        key_blob, err = _ensure_key(home)
        if not key_blob:
            print(f"enclave key unavailable: {err}", file=sys.stderr)
            return 1
        pub, err = _pubkey(key_blob)
        if not pub:
            print(f"pubkey failed: {err}", file=sys.stderr)
            return 1
        helper = _helper()
        proc = kc.run_cli([helper, "encrypt", pub], stdin_data=value.encode())
        if proc.returncode != 0:
            print("encrypt failed:",
                  (proc.stderr or b"").decode("utf-8", "replace").strip(),
                  file=sys.stderr)
            return 1
        ct = (proc.stdout or b"").decode().strip()
        dest = kc.ct_path(home, env_name)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(ct + "\n")
        dest.chmod(0o600)
        kc.register_item(home, {"env": env_name, "mode": mode})
        print(f"stored {env_name} (enclave-encrypted, {dest})")

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
    kc.session_clear(_home_path(), targets)
    print(f"cleared {len(targets)} unlock session(s)")
    return 0


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
                state = "unlocked" if value else f"locked ({err})"
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
    kc.kc_delete(args.service or kc.DEFAULT_SERVICE, args.account or env_name)
    ct = kc.ct_path(home, env_name)
    if ct.is_file():
        ct.unlink()
    kc.session_clear(home, [env_name])
    kc.unregister_item(home, env_name)
    print(f"deleted {env_name} (keychain item, ciphertext, session, registration)")
    return 0


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


def cli_dispatch(args) -> int:
    fn = getattr(args, "kc_fn", None)
    if fn is None:
        return cmd_setup(args)
    return fn(args)
