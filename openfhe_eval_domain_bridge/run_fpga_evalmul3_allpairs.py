#!/usr/bin/env python3
"""Compatibility launcher; use pynq_butterfly.cli.run_fpga_evalmul3_allpairs."""
import runpy
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "host" / "openfhe" / "python"))
runpy.run_module("pynq_butterfly.cli.run_fpga_evalmul3_allpairs", run_name="__main__")
