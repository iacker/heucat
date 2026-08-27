"""Test bootstrap: put the hermes-agent checkout and the plugin on sys.path.

HERMES_AGENT_SRC must point at a hermes-agent checkout that has the
SecretSource interface (agent/secret_sources/base.py). Default tries the
standard install location.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

_DEFAULT = Path.home() / ".hermes" / "hermes-agent"
_SRC = Path(os.environ.get("HERMES_AGENT_SRC", _DEFAULT)).expanduser()

if not (_SRC / "agent" / "secret_sources" / "base.py").is_file():
    raise RuntimeError(
        f"HERMES_AGENT_SRC ({_SRC}) is not a hermes-agent checkout with the "
        "SecretSource interface; set HERMES_AGENT_SRC"
    )

sys.path.insert(0, str(_SRC))

# Import the plugin as a package named 'keychain_plugin' regardless of the
# directory name (which may contain hyphens).
import importlib.util

_PLUGIN_DIR = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "keychain_plugin", _PLUGIN_DIR / "__init__.py",
    submodule_search_locations=[str(_PLUGIN_DIR)],
)
assert _spec is not None and _spec.loader is not None
keychain_plugin = importlib.util.module_from_spec(_spec)
sys.modules["keychain_plugin"] = keychain_plugin
_spec.loader.exec_module(keychain_plugin)
