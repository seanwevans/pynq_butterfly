#!/usr/bin/env python3
"""Compatibility launcher; use pynq_butterfly.cli.prepare_evalmul3_bv_relinearized_vectors."""
import runpy
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "host" / "openfhe" / "python"))
runpy.run_module("pynq_butterfly.cli.prepare_evalmul3_bv_relinearized_vectors", run_name="__main__")
