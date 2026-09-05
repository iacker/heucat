"""Failure-path tests, no real Keychain or credentials."""
import json
import pytest
from keychain_plugin import kc_common as kc


@pytest.fixture
def store(monkeypatch):
    values = {}
    monkeypatch.setattr(kc, 'kc_read', lambda s, a, k='': (values.get(a), ''))
    monkeypatch.setattr(kc, 'kc_write', lambda s, a, v, k='': values.__setitem__(a, v) or '')
    monkeypatch.setattr(kc, 'kc_delete', lambda s, a, k='': (values.pop(a, None), '')[1])
    return values


def test_failed_replacement_preserves_old_session(tmp_path, monkeypatch, store):
    assert kc.session_write(tmp_path, 'TEST', 'old' * 200, 300) == ''
    original = dict(store)
    def fail_second_part(s, a, v, k=''):
        if ':part:' in a and a.endswith(':1'):
            return 'write denied'
        store[a] = v
        return ''
    monkeypatch.setattr(kc, 'kc_write', fail_second_part)
    assert kc.session_write(tmp_path, 'TEST', 'new' * 200, 300) == 'write denied'
    assert store == original
    assert kc.session_read(tmp_path, 'TEST') == ('old' * 200, '')


def test_short_write_failure_is_not_success(tmp_path, monkeypatch, store):
    monkeypatch.setattr(kc, 'kc_write', lambda *a: 'denied')
    assert kc.session_write(tmp_path, 'TEST', 'v', 300) == 'denied'


@pytest.mark.parametrize('raw', ['@chunks:999999999', '@chunks:-1', '@chunks:0', '@chunks:2:bad', '{"exp":4102444800}'])
def test_corrupt_sessions_fail_closed(tmp_path, store, raw):
    store[kc.session_account(tmp_path, 'TEST')] = raw
    value, error = kc.session_read(tmp_path, 'TEST')
    assert value is None and error


def test_unicode_and_short_replacement_remove_old_parts(tmp_path, store):
    value = '\u00e9\U0001f512' * 150
    assert kc.session_write(tmp_path, 'TEST', value, 300) == ''
    assert kc.session_read(tmp_path, 'TEST') == (value, '')
    assert all(len(v.encode()) <= 96 for v in store.values())
    assert kc.session_write(tmp_path, 'TEST', 'short', 300) == ''
    assert len(store) == 1
    assert kc.session_read(tmp_path, 'TEST') == ('short', '')
