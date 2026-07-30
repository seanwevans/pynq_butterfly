#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys


def read_summary(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or "=" not in line:
            continue

        key, value = line.split("=", 1)
        values[key] = value

    return values


def require_equal(
    values: dict[str, str],
    key: str,
    expected: str,
) -> None:
    actual = values.get(key)

    if actual != expected:
        raise RuntimeError(
            f"{key}: expected {expected!r}, received {actual!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path(__file__).resolve().parent,
    )
    parser.add_argument(
        "--minimum-wns",
        type=float,
        default=0.0,
    )
    args = parser.parse_args()

    summary = (
        args.repo
        / "reports"
        / "poly_mul4096_four_butterfly_pipeline_implemented"
        / "implementation_summary.txt"
    )

    if not summary.is_file():
        raise RuntimeError(f"summary not found: {summary}")

    values = read_summary(summary)

    require_equal(values, "implementation_status", "Complete")
    require_equal(values, "n", "4096")
    require_equal(values, "shared_arithmetic_lanes", "4")
    require_equal(values, "barrett_pipeline_latency", "7")
    require_equal(values, "arithmetic_vector_latency", "9")
    require_equal(values, "initiation_interval", "1")
    require_equal(values, "modular_multiplications_per_product", "90112")
    require_equal(values, "dsp", "64")
    require_equal(values, "ramb18", "16")
    require_equal(values, "ramb36", "32")

    wns = float(values["wns_ns"])

    projected_dsp = int(values["two_tower_dsp_projection"])
    available_dsp = 220
    remaining_dsp = available_dsp - projected_dsp

    print("Four-butterfly pipelined polynomial implementation")
    print(f"  LUT:                 {values.get('lut', 'UNKNOWN')}")
    print(f"  registers:           {values.get('registers', 'UNKNOWN')}")
    print(f"  CARRY4:              {values.get('carry4', 'UNKNOWN')}")
    print(f"  DSP48E1:             {values['dsp']}")
    print(f"  RAMB18E1:            {values['ramb18']}")
    print(f"  RAMB36E1:            {values['ramb36']}")
    print(f"  two-tower DSPs:      {projected_dsp}")
    print(f"  DSPs remaining:      {remaining_dsp}")
    print(f"  WNS:                 {wns:+.3f} ns")
    print(f"  datapath:            {values.get('datapath_ns', 'UNKNOWN')} ns")
    print(f"  start:               {values.get('startpoint', 'UNKNOWN')}")
    print(f"  end:                 {values.get('endpoint', 'UNKNOWN')}")

    if projected_dsp > available_dsp:
        raise RuntimeError(
            f"two-tower DSP projection {projected_dsp} "
            f"exceeds device capacity {available_dsp}"
        )

    if wns < args.minimum_wns:
        raise RuntimeError(
            f"WNS {wns:+.3f} ns is below required "
            f"{args.minimum_wns:+.3f} ns"
        )

    print("PASS: full polynomial core meets physical requirements")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
