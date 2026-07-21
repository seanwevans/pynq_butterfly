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


def require_equal(values: dict[str, str], key: str, expected: str) -> None:
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
        / "modmul_barrett60_pipeline_split_implemented"
        / "implementation_summary.txt"
    )

    if not summary.is_file():
        raise RuntimeError(f"summary not found: {summary}")

    values = read_summary(summary)

    require_equal(values, "implementation_status", "Complete")
    require_equal(values, "pipeline_latency", "7")
    require_equal(values, "initiation_interval", "1")
    require_equal(values, "dsp", "16")
    require_equal(values, "ramb18", "0")
    require_equal(values, "ramb36", "0")

    wns = float(values["wns_ns"])

    print("Barrett split-pipeline implementation")
    print(f"  LUT:       {values.get('lut', 'UNKNOWN')}")
    print(f"  registers: {values.get('registers', 'UNKNOWN')}")
    print(f"  CARRY4:    {values.get('carry4', 'UNKNOWN')}")
    print(f"  DSP48E1:   {values['dsp']}")
    print(f"  WNS:       {wns:+.3f} ns")
    print(f"  datapath:  {values.get('datapath_ns', 'UNKNOWN')} ns")
    print(f"  start:     {values.get('startpoint', 'UNKNOWN')}")
    print(f"  end:       {values.get('endpoint', 'UNKNOWN')}")

    if wns < args.minimum_wns:
        raise RuntimeError(
            f"WNS {wns:+.3f} ns is below required "
            f"{args.minimum_wns:+.3f} ns"
        )

    print("PASS: implementation meets the checkpoint requirements")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
