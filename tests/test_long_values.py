"""Regression: macOS `security` truncates prompted passwords at 128 chars.

Before this was caught, a long OAuth token was stored truncated and exited 0,
producing "corrupt session record" at read time and losing the value. These
tests pin both halves of the fix: writes verify themselves, and long session
payloads spill to a file instead of being silently cut.

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


def test_long_session_round_trips_via_spill(home: Path):
    """A long token must survive unlock -> read, which is what broke."""
    env = "PYTEST_LONG_TOKEN"
    try:
        assert kc.session_write(home, env, LONG, 3600) == ""
        value, err = kc.session_read(home, env)
        assert err == ""
        assert value == LONG, "long session value did not round-trip"
        assert kc._spill_path(home, env).is_file()
        assert kc._spill_path(home, env).stat().st_mode & 0o777 == 0o600
    finally:
        kc.session_clear(home, [env])


def test_short_session_stays_in_keychain(home: Path):
    env = "PYTEST_SHORT_TOKEN"
    try:
        assert kc.session_write(home, env, SHORT, 3600) == ""
        assert kc.session_read(home, env)[0] == SHORT
        assert not kc._spill_path(home, env).exists(), "short value should not spill"
    finally:
        kc.session_clear(home, [env])


def test_session_clear_removes_spill_file(home: Path):
    env = "PYTEST_CLEAR_TOKEN"
    kc.session_write(home, env, LONG, 3600)
    assert kc._spill_path(home, env).is_file()
    kc.session_clear(home, [env])
    assert not kc._spill_path(home, env).exists()
    assert kc.session_read(home, env)[0] is None
