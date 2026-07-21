#!/usr/bin/env python3
from pathlib import Path

path = Path("rtl/poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core.sv")
if not path.is_file():
    raise SystemExit(f"missing committed handoff core: {path}")

text = path.read_text(encoding="utf-8")

required = (
    "module poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core",
    "output logic [3:0][31:0]  handoff_read_data",
    "ntt4096_eight_bank_coeff_store_runtime_handoff4 coefficient_store_a",
    "ntt4096_eight_bank_coeff_store_runtime_handoff4 coefficient_store_b",
    ".handoff_read_data_valid (handoff_read_data_valid)",
    ".handoff_read_data       (handoff_read_data)",
)

for token in required:
    if token not in text:
        raise SystemExit(
            f"handoff core validation failed: missing {token!r}"
        )

for forbidden in (
    "a_store_effective_write",
    "logic [7:0][11:0] handoff_read_address",
    "assign handoff_read_data =\n        a_store_read_data[3:0]",
):
    if forbidden in text:
        raise SystemExit(
            f"handoff core validation failed: stale path {forbidden!r}"
        )

print(f"validated dedicated four-wide handoff read in {path}")
