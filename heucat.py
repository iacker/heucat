#!/usr/bin/env python3
"""Standalone `hermes keychain` without booting Hermes (~50 ms instead of ~5 s).

Same subcommands as `hermes keychain`; HERMES_HOME selects the profile.
The menu-bar app calls this, never the full Hermes CLI.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import kc_cli  # noqa: E402

parser = argparse.ArgumentParser(prog="heucat")
kc_cli.setup_cli_parser(parser)
sys.exit(kc_cli.cli_dispatch(parser.parse_args()))
