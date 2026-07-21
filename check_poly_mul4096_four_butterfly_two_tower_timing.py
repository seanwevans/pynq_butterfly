#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import sys


def read_summary(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or "=" not in line:
            continue

        key, value = line.split("=", 1)
        result[key] = value

    return result


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

    root = (
        args.repo
        / "reports"
        / "poly_mul4096_four_butterfly_two_tower_timing_recovery"
    )

    best_summary = (
        root
        / "best"
        / "implementation_summary.txt"
    )

    results_path = (
        root
        / "strategy_results.tsv"
    )

    if not best_summary.is_file():
        raise RuntimeError(
            f"best implementation summary not found: {best_summary}"
        )

    values = read_summary(best_summary)

    if values.get("implementation_status") != "Complete":
        raise RuntimeError(
            "timing-recovery implementation did not complete"
        )

    if values.get("product_cycles") != "22968":
        raise RuntimeError(
            f"unexpected product cycle count: "
            f"{values.get('product_cycles')!r}"
        )

    if values.get("dsp") != "128":
        raise RuntimeError(
            f"unexpected DSP count: {values.get('dsp')!r}"
        )

    if values.get("ramb18") != "32":
        raise RuntimeError(
            f"unexpected RAMB18 count: {values.get('ramb18')!r}"
        )

    if values.get("ramb36") != "64":
        raise RuntimeError(
            f"unexpected RAMB36 count: {values.get('ramb36')!r}"
        )

    wns = float(values["wns_ns"])

    print("Two-tower timing-recovery result")
    print(f"  best strategy: {values['best_strategy']}")
    print(f"  WNS:           {wns:+.3f} ns")
    print(f"  datapath:      {values['datapath_ns']} ns")
    print(f"  logic levels:  {values['logic_levels']}")
    print(f"  start:         {values['startpoint']}")
    print(f"  end:           {values['endpoint']}")
    print(f"  best DCP:      {values['checkpoint']}")

    if results_path.is_file():
        print()
        print(results_path.read_text(encoding="utf-8").rstrip())

    if wns < args.minimum_wns:
        raise RuntimeError(
            f"best WNS {wns:+.3f} ns is below required "
            f"{args.minimum_wns:+.3f} ns"
        )

    print()
    print("PASS: at least one implementation strategy closes 100 MHz")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
