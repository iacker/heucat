"""Hermetic tests for KeychainSource: conformance kit + behavior.

No real keychain, no real enclave — subprocess and session calls are
monkeypatched. Run:

    HERMES_AGENT_SRC=~/.hermes/hermes-agent PYTHONPATH=~/.hermes/hermes-agent python3 -m pytest tests/ -v
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# conformance kit lives in the hermes-agent checkout's tests/
_SRC = Path(os.environ.get("HERMES_AGENT_SRC",
                           Path.home() / ".hermes" / "hermes-agent")).expanduser()
sys.path.insert(0, str(_SRC / "tests" / "secret_sources"))

from conformance import SecretSourceConformance  # noqa: E402

from keychain_plugin.kc_source import KeychainSource  # noqa: E402
from keychain_plugin import kc_cli  # noqa: E402
from keychain_plugin import kc_common as kc  # noqa: E402
from agent.secret_sources.base import ErrorKind, FetchResult  # noqa: E402


class TestKeychainConformance(SecretSourceConformance):
    @pytest.fixture
    def source(self):
        return KeychainSource()


class TestPlainMode:
    @pytest.fixture
    def source(self):
        return KeychainSource()

    @pytest.fixture(autouse=True)
    def macos(self, monkeypatch):
        monkeypatch.setattr(kc, "is_macos", lambda: True)
        monkeypatch.setattr(os.path, "exists",
                            lambda p: True if p == kc.SECURITY_BIN
                            else os.path.__dict__["exists"](p))

    def test_reads_configured_accounts(self, source, tmp_path, monkeypatch):
        store = {("hermes", "API_A"): "value-a", ("hermes", "API_B"): "value-b"}
        monkeypatch.setattr(
            kc, "kc_read",
            lambda s, a, k="": (store.get((s, a)), "" if (s, a) in store else "not found"),
        )
        cfg = {"enabled": True, "accounts": ["API_A", "API_B"]}
        result = source.fetch(cfg, tmp_path)
        assert result.ok, result.error
        assert result.secrets == {"API_A": "value-a", "API_B": "value-b"}

    def test_custom_account_and_service(self, source, tmp_path, monkeypatch):
        calls = []

        def fake_read(service, account, keychain=""):
            calls.append((service, account, keychain))
            return "v", ""

        monkeypatch.setattr(kc, "kc_read", fake_read)
        cfg = {
            "enabled": True,
            "service": "custom-svc",
            "default_keychain": "/tmp/x.keychain",
            "items": [{"env": "MY_KEY", "account": "weird-name"}],
        }
        result = source.fetch(cfg, tmp_path)
        assert result.secrets == {"MY_KEY": "v"}
        assert calls == [("custom-svc", "weird-name", "/tmp/x.keychain")]

    def test_missing_item_warns_but_others_succeed(self, source, tmp_path, monkeypatch):
        monkeypatch.setattr(
            kc, "kc_read",
            lambda s, a, k="": ("v", "") if a == "GOOD" else (None, "not found"),
        )
        cfg = {"enabled": True, "accounts": ["GOOD", "MISSING"]}
        result = source.fetch(cfg, tmp_path)
        assert result.ok
        assert result.secrets == {"GOOD": "v"}
        assert any("MISSING" in w for w in result.warnings)

    def test_all_failed_reports_auth_failed(self, source, tmp_path, monkeypatch):
        monkeypatch.setattr(kc, "kc_read", lambda s, a, k="": (None, "denied"))
        cfg = {"enabled": True, "accounts": ["A", "B"]}
        result = source.fetch(cfg, tmp_path)
        assert not result.ok
        assert result.error_kind == ErrorKind.AUTH_FAILED
        assert not result.secrets

    def test_empty_value_warns_and_skips(self, source, tmp_path, monkeypatch):
        monkeypatch.setattr(kc, "kc_read", lambda s, a, k="": ("", ""))
        cfg = {"enabled": True, "accounts": ["EMPTY_ONE"]}
        result = source.fetch(cfg, tmp_path)
        assert "EMPTY_ONE" not in result.secrets
        assert any("empty" in w.lower() for w in result.warnings)


class TestEnclaveMode:
    @pytest.fixture
    def source(self):
        return KeychainSource()

    @pytest.fixture(autouse=True)
    def macos(self, monkeypatch):
        monkeypatch.setattr(kc, "is_macos", lambda: True)
        monkeypatch.setattr(os.path, "exists",
                            lambda p: True if p == kc.SECURITY_BIN
                            else os.path.__dict__["exists"](p))

    def test_unlocked_session_provides_secret(self, source, tmp_path, monkeypatch):
        monkeypatch.setattr(kc, "session_read", lambda home, env: ("tok-123", ""))
        cfg = {"enabled": True, "items": [{"env": "GH_TOKEN", "mode": "enclave"}]}
        result = source.fetch(cfg, tmp_path)
        assert result.ok
        assert result.secrets == {"GH_TOKEN": "tok-123"}

    def test_locked_session_is_auth_expired_never_prompt(self, source, tmp_path,
                                                         monkeypatch):
        monkeypatch.setattr(kc, "session_read",
                            lambda home, env: (None, "no unlock session"))
        cfg = {"enabled": True, "items": [{"env": "GH_TOKEN", "mode": "enclave"}]}
        result = source.fetch(cfg, tmp_path)
        assert not result.ok
        assert result.error_kind == ErrorKind.AUTH_EXPIRED
        assert "unlock" in source.remediation(result.error_kind, cfg).lower()

    def test_mixed_locked_and_plain_partial_success(self, source, tmp_path,
                                                    monkeypatch):
        monkeypatch.setattr(kc, "kc_read", lambda s, a, k="": ("plain-v", ""))
        monkeypatch.setattr(kc, "session_read",
                            lambda home, env: (None, "unlock session expired"))
        cfg = {
            "enabled": True,
            "accounts": ["PLAIN_KEY"],
            "items": [{"env": "SE_KEY", "mode": "enclave"}],
        }
        result = source.fetch(cfg, tmp_path)
        assert result.ok  # partial success is not a startup failure
        assert result.secrets == {"PLAIN_KEY": "plain-v"}
        assert any("SE_KEY" in w and "unlock" in w for w in result.warnings)

    def test_access_log_names_keys_never_values(self, source, tmp_path, monkeypatch):
        import json
        import stat

        monkeypatch.setattr(kc, "kc_read", lambda s, a, k="": ("plain-v", ""))
        monkeypatch.setattr(kc, "session_read", lambda home, env: (None, "locked"))
        cfg = {"accounts": ["PLAIN_KEY"], "items": [{"env": "SE_KEY", "mode": "enclave"}]}
        source.fetch(cfg, tmp_path)
        source.fetch(cfg, tmp_path)
        log = kc.access_log_path(tmp_path)
        lines = log.read_text().splitlines()
        assert len(lines) == 2
        entry = json.loads(lines[-1])
        assert entry["served"] == ["PLAIN_KEY"] and entry["locked"] == ["SE_KEY"]
        assert "plain-v" not in log.read_text()
        assert stat.S_IMODE(log.stat().st_mode) == 0o600


class TestNonMacos:
    def test_not_macos_is_clean_error(self, tmp_path, monkeypatch):
        monkeypatch.setattr(kc, "is_macos", lambda: False)
        result = KeychainSource().fetch({"enabled": True, "accounts": ["X"]},
                                        tmp_path)
        assert not result.ok
        assert result.error_kind == ErrorKind.NOT_CONFIGURED


class TestConfigParsing:
    def test_registered_items_are_atomic_private_and_merged(self, tmp_path):
        kc.register_item(tmp_path, {"env": "AUTO_TOKEN", "mode": "enclave"})
        path = kc.registry_path(tmp_path)
        assert path.stat().st_mode & 0o777 == 0o600
        assert kc.merge_registered_items({}, tmp_path)["items"] == [
            {"env": "AUTO_TOKEN", "mode": "enclave"}
        ]

    def test_unregister_removes_only_target(self, tmp_path):
        kc.register_item(tmp_path, {"env": "ONE", "mode": "plain"})
        kc.register_item(tmp_path, {"env": "TWO", "mode": "enclave"})
        kc.unregister_item(tmp_path, "ONE")
        assert kc.registered_items(tmp_path) == [{"env": "TWO", "mode": "enclave"}]

    def test_registry_overrides_stale_yaml_entry(self, tmp_path):
        kc.register_item(tmp_path, {"env": "TOKEN", "mode": "enclave"})
        merged = kc.merge_registered_items(
            {"items": [{"env": "TOKEN", "mode": "plain"}]}, tmp_path
        )
        assert merged["items"] == [{"env": "TOKEN", "mode": "enclave"}]

    def test_dedup_keeps_first(self):
        items, warnings = kc.parse_items(
            {"accounts": ["A", "A"], "items": [{"env": "A", "mode": "enclave"}]}
        )
        assert len(items) == 1
        assert items[0]["mode"] == "plain"
        assert len(warnings) == 2

    def test_invalid_names_skipped(self):
        items, warnings = kc.parse_items(
            {"accounts": ["ok_NAME", "bad-name", "", 42, None]}
        )
        assert [i["env"] for i in items] == ["ok_NAME"]
        assert len(warnings) == 4

    def test_unknown_mode_skipped(self):
        items, warnings = kc.parse_items(
            {"items": [{"env": "X", "mode": "quantum"}]}
        )
        assert items == []
        assert any("quantum" in w for w in warnings)

    def test_malformed_section_shapes(self):
        for cfg in ({}, {"accounts": "nope"}, {"items": 3},
                    {"accounts": None, "items": None}):
            items, _ = kc.parse_items(cfg)
            assert items == []
        items, warnings = kc.parse_items("not-a-dict")  # type: ignore[arg-type]
        assert items == [] and warnings

    def test_session_ttl_defensive(self):
        assert kc.session_ttl({}) == kc.DEFAULT_SESSION_TTL
        assert kc.session_ttl({"session_ttl_seconds": "junk"}) == kc.DEFAULT_SESSION_TTL
        assert kc.session_ttl({"session_ttl_seconds": -5}) == kc.DEFAULT_SESSION_TTL
        assert kc.session_ttl({"session_ttl_seconds": 60}) == 60

    def test_ciphertext_path_rejects_traversal(self, tmp_path):
        with pytest.raises(ValueError):
            kc.ct_path(tmp_path, "../../outside")
        assert kc.ct_path(tmp_path, "VALID_NAME").parent == tmp_path / "keychain" / "secrets"


class TestNoPromptGuarantee:
    """The startup path must never spawn anything that can block on a prompt."""

    def test_fetch_never_calls_helper(self, tmp_path, monkeypatch):
        """fetch() must not invoke the Swift helper (which prompts) at all."""
        monkeypatch.setattr(kc, "is_macos", lambda: True)
        monkeypatch.setattr(os.path, "exists", lambda p: True)
        called = []
        monkeypatch.setattr(kc, "helper_path",
                            lambda: called.append(True) or None)
        monkeypatch.setattr(kc, "session_read", lambda home, env: (None, "locked"))
        monkeypatch.setattr(kc, "kc_read", lambda s, a, k="": (None, "x"))
        KeychainSource().fetch(
            {"enabled": True,
             "accounts": ["A"],
             "items": [{"env": "B", "mode": "enclave"}]},
            tmp_path,
        )
        assert called == [], "fetch() must never touch the interactive helper"

    def test_run_cli_closes_stdin_by_default(self, monkeypatch):
        captured = {}

        def fake_run(argv, **kwargs):
            captured.update(kwargs)

            class P:
                returncode = 0
                stdout = b""
                stderr = b""

            return P()

        import subprocess as sp
        monkeypatch.setattr(sp, "run", fake_run)
        kc.run_cli(["/bin/echo", "x"])
        assert captured.get("stdin") == sp.DEVNULL

    def test_keychain_write_never_puts_secret_in_argv(self, monkeypatch):
        captured = {}

        class P:
            returncode = 0
            stdout = b""
            stderr = b""

        def fake_run(argv, **kwargs):
            # kc_write verifies its own write by reading back, so the fake has
            # to behave like a real keychain: remember on add, replay on find.
            if "add-generic-password" in argv:
                captured["argv"] = argv
                captured.update(kwargs)
                captured["stored"] = kwargs.get("stdin_data", b"").split(b"\n")[0]
            out = type("P", (), {"returncode": 0, "stderr": b"",
                                 "stdout": captured.get("stored", b"") + b"\n"})
            return out() if "find-generic-password" in argv else P()

        monkeypatch.setattr(kc, "run_cli", fake_run)
        secret = "sensitive-value-123"
        assert kc.kc_write("svc", "account", secret) == ""
        assert secret not in captured["argv"]
        assert captured["stdin_data"] == (secret + "\n" + secret + "\n").encode()

    def test_store_stdin_bypasses_getpass_and_keeps_secret_out_of_argv(
        self, tmp_path, monkeypatch
    ):
        import argparse
        import io

        secret = "gui-piped-sensitive-value"
        captured = {}
        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr("sys.stdin", io.StringIO(secret + "\n"))
        monkeypatch.setattr(kc_cli.getpass, "getpass", lambda _: pytest.fail("getpass called"))
        monkeypatch.setattr(kc, "kc_write", lambda service, account, value, keychain="": captured.update(
            service=service, account=account, value=value
        ) or "")
        monkeypatch.setattr(kc_cli, "_load_cfg", lambda: {})
        args = argparse.Namespace(
            env_name="GUI_TOKEN", enclave=False, service=None, account=None, stdin=True
        )

        assert kc_cli.cmd_store(args) == 0
        assert captured["value"] == secret
        assert secret not in vars(args).values()

    def test_store_update_preserves_custom_keychain_location(self, tmp_path, monkeypatch):
        import argparse
        import io

        captured = {}
        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr("sys.stdin", io.StringIO("replacement\n"))
        monkeypatch.setattr(kc_cli, "_load_cfg", lambda: {"items": [{
            "env": "CUSTOM_TOKEN", "mode": "plain", "service": "custom-service",
            "account": "custom-account", "keychain": "custom.keychain-db",
        }]})
        monkeypatch.setattr(kc, "kc_write", lambda s, a, v, k="": captured.update(
            service=s, account=a, keychain=k,
        ) or "")
        args = argparse.Namespace(
            env_name="CUSTOM_TOKEN", enclave=False, service=None, account=None, stdin=True,
        )

        assert kc_cli.cmd_store(args) == 0
        assert captured == {
            "service": "custom-service", "account": "custom-account",
            "keychain": "custom.keychain-db",
        }

    def test_store_rejects_implicit_mode_change(self, tmp_path, monkeypatch):
        import argparse

        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr(kc_cli, "_load_cfg", lambda: {
            "items": [{"env": "TOKEN", "mode": "plain"}],
        })
        args = argparse.Namespace(
            env_name="TOKEN", enclave=True, service=None, account=None, stdin=True,
        )
        assert kc_cli.cmd_store(args) == 2

    def test_delete_uses_registered_custom_location(self, tmp_path, monkeypatch):
        import argparse

        deleted = []
        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr(kc_cli, "_load_cfg", lambda: {"items": [{
            "env": "CUSTOM_TOKEN", "mode": "plain", "service": "custom-service",
            "account": "custom-account", "keychain": "custom.keychain-db",
        }]})
        monkeypatch.setattr(kc, "kc_delete", lambda s, a, k="": deleted.append((s, a, k)) or "")
        args = argparse.Namespace(env_name="CUSTOM_TOKEN", service=None, account=None)

        assert kc_cli.cmd_delete(args) == 0
        assert ("custom-service", "custom-account", "custom.keychain-db") in deleted

    def test_session_accounts_are_isolated_by_profile(self, tmp_path):
        profile_a = tmp_path / "profiles" / "a"
        profile_b = tmp_path / "profiles" / "b"
        assert kc.session_account(profile_a, "GITHUB_TOKEN") != kc.session_account(
            profile_b, "GITHUB_TOKEN"
        )
        assert kc.session_account(profile_a, "GITHUB_TOKEN").endswith(":GITHUB_TOKEN")


class TestSessionExpiry:
    """`unlock` is worthless if you cannot see when it lapses."""

    def test_expires_in_counts_down_and_clears(self, tmp_path, monkeypatch):
        import kc_common as kc
        store = {}
        monkeypatch.setattr(kc, "kc_write", lambda s, a, v: store.__setitem__(a, v) or "")
        monkeypatch.setattr(kc, "kc_read", lambda s, a, k=None: (store.get(a), "" if a in store else "missing"))
        monkeypatch.setattr(kc, "kc_delete", lambda s, a, k=None: (store.pop(a, None), "")[1])

        kc.session_write(tmp_path, "TOKEN", "v", 3600)
        left = kc.session_expires_in(tmp_path, "TOKEN")
        assert 3590 <= left <= 3600

        kc.session_write(tmp_path, "GONE", "v", -1)          # already expired
        assert kc.session_read(tmp_path, "GONE") == (None, "unlock session expired")
        assert kc.session_expires_in(tmp_path, "GONE") is None   # reading it purged the record
        assert kc.session_expires_in(tmp_path, "NEVER_STORED") is None

    def test_human_delay_formats(self):
        from kc_cli import _human_delay
        assert _human_delay(27000) == "7h30m"
        assert _human_delay(900) == "15m"
        assert _human_delay(40) == "<1m"


class TestProviderProbe:
    def test_http_403_is_not_reported_as_authenticated(self, tmp_path, monkeypatch):
        import argparse
        from email.message import Message
        import urllib.error
        import urllib.request

        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr(kc_cli, "_effective_cfg", lambda: {
            "items": [{"env": "OPENAI_API_KEY", "mode": "plain"}],
        })
        monkeypatch.setattr(kc_cli, "_read_value", lambda home, item: ("secret", ""))
        monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **k: (_ for _ in ()).throw(
            urllib.error.HTTPError("url", 403, "forbidden", Message(), None)
        ))

        assert kc_cli.cmd_test(argparse.Namespace(env_name="OPENAI_API_KEY")) == 1

    def test_http_429_is_inconclusive(self, tmp_path, monkeypatch):
        import argparse
        from email.message import Message
        import urllib.error
        import urllib.request

        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr(kc_cli, "_effective_cfg", lambda: {
            "items": [{"env": "OPENAI_API_KEY", "mode": "plain"}],
        })
        monkeypatch.setattr(kc_cli, "_read_value", lambda home, item: ("secret", ""))
        monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **k: (_ for _ in ()).throw(
            urllib.error.HTTPError("url", 429, "limited", Message(), None)
        ))

        assert kc_cli.cmd_test(argparse.Namespace(env_name="OPENAI_API_KEY")) == 3


class TestExport:
    def test_export_quotes_and_shells_out_readable_secrets(self, tmp_path, monkeypatch, capsys):
        import argparse
        monkeypatch.setenv("HERMES_HOME", str(tmp_path))
        monkeypatch.setattr(kc_cli, "_effective_cfg", lambda: {
            "items": [
                {"env": "OK_KEY", "mode": "plain"},
                {"env": "LOCKED_KEY", "mode": "enclave"},
            ],
        })
        vals = {"OK_KEY": "it's a \"secret\"", "LOCKED_KEY": None}
        monkeypatch.setattr(kc_cli, "_read_value",
                            lambda home, item: (vals[item["env"]], "" if vals[item["env"]] else "locked"))
        rc = kc_cli.cmd_export(argparse.Namespace(dotenv=False))
        out = capsys.readouterr()
        assert rc == 1  # one locked -> non-zero
        assert out.out == "export OK_KEY='it'\\''s a \"secret\"'\n"
        assert "LOCKED_KEY" in out.err and "OK_KEY" not in out.err
        assert kc_cli.cmd_export(argparse.Namespace(dotenv=True)) == 1
        assert capsys.readouterr().out.startswith("OK_KEY=")