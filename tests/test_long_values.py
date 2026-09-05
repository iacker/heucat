"""Regression tests for macOS Keychain's 128-character prompt limit.

Writes verify themselves, and long session payloads are split across Keychain
items so plaintext never spills to disk.

Run: python3 -m pytest tests/test_long_values.py -q
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import kc_common as kc  # noqa: E402

SERVICE = "hermes-kc-pytest"
LONG = "t" * 900          # well past the 128-char ceiling
SHORT = "short-value"


def _cleanup(account: str) -> None:
    kc.kc_delete(SERVICE, account)


@pytest.fixture
def home(tmp_path: Path) -> Path:
    return tmp_path


def test_short_value_round_trips():
    account = "pytest-short"
    try:
        assert kc.kc_write(SERVICE, account, SHORT) == ""
        assert kc.kc_read(SERVICE, account)[0] == SHORT
    finally:
        _cleanup(account)


def test_long_value_is_rejected_not_silently_truncated():
    """The whole point: a value security cannot store must report an error,
    never look like success while holding 128 characters."""
    account = "pytest-long"
    try:
        err = kc.kc_write(SERVICE, account, LONG)
        assert err != "", "long write reported success despite truncation"
        assert "truncated" in err
        # And nothing corrupt is left behind.
        assert kc.kc_read(SERVICE, account)[0] is None
    finally:
        _cleanup(account)


def test_long_session_round_trips_inside_keychain(home: Path):
    """Long sessions are chunked in Keychain and never written to disk."""
    env = "PYTEST_LONG_TOKEN"
    try:
        assert kc.session_write(home, env, LONG, 3600) == ""
        value, err = kc.session_read(home, env)
        assert err == ""
        assert value == LONG, "long session value did not round-trip"
        assert not kc._spill_path(home, env).exists()
        manifest, _ = kc.kc_read(kc.SESSION_SERVICE, kc.session_account(home, env))
        assert manifest and manifest.startswith(kc.SESSION_CHUNK_PREFIX)
    finally:
        kc.session_clear(home, [env])


def test_short_session_stays_in_one_keychain_item(home: Path):
    env = "PYTEST_SHORT_TOKEN"
    try:
        assert kc.session_write(home, env, SHORT, 3600) == ""
        assert kc.session_read(home, env)[0] == SHORT
        manifest, _ = kc.kc_read(kc.SESSION_SERVICE, kc.session_account(home, env))
        assert manifest and not manifest.startswith(kc.SESSION_CHUNK_PREFIX)
        assert not kc._spill_path(home, env).exists()
    finally:
        kc.session_clear(home, [env])


def test_session_clear_removes_chunks(home: Path):
    env = "PYTEST_CLEAR_TOKEN"
    assert kc.session_write(home, env, LONG, 3600) == ""
    account = kc.session_account(home, env)
    manifest, _ = kc.kc_read(kc.SESSION_SERVICE, account)
    count = kc._chunk_count(manifest)
    assert count > 1
    kc.session_clear(home, [env])
    assert all(
        kc.kc_read(kc.SESSION_SERVICE, kc._chunk_account(account, index, manifest))[0] is None
        for index in range(count)
    )
    assert kc.session_read(home, env)[0] is None


def test_legacy_spill_is_migrated_and_removed(home: Path):
    env = "PYTEST_LEGACY_TOKEN"
    account = kc.session_account(home, env)
    spill = kc._spill_path(home, env)
    payload = '{"v":"' + LONG + '","exp":4102444800}'
    try:
        spill.parent.mkdir(parents=True)
        spill.write_text(payload)
        assert kc.kc_write(kc.SESSION_SERVICE, account, kc.SESSION_SPILL_PREFIX + spill.name) == ""

        assert kc.session_read(home, env) == (LONG, "")
        assert not spill.exists()
        manifest, _ = kc.kc_read(kc.SESSION_SERVICE, account)
        assert kc._chunk_count(manifest) > 1
    finally:
        kc.session_clear(home, [env])
