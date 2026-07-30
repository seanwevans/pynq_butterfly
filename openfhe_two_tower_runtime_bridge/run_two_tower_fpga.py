#!/usr/bin/env python3
"""Compatibility launcher; use pynq_butterfly.cli.run_two_tower_fpga."""
import runpy
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "host" / "openfhe" / "python"))
runpy.run_module("pynq_butterfly.cli.run_two_tower_fpga", run_name="__main__")
