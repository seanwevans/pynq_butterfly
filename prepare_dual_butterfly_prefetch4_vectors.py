#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

import numpy as np


N = 4096
PROFILE_FILES = (
    "twist_factors.mem",
    "forward_twiddles.mem",
    "inverse_twiddles.mem",
    "inverse_scale_factors.mem",
    "profile.json",
)


def read_u32le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def write_mem(path: Path, values: np.ndarray) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as output:
        for value in values:
            output.write(f"{int(value):08x}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--products", type=int, default=4)
    args = parser.parse_args()

    source = args.input.resolve()
    output = args.output.resolve()

    if args.products != 4:
        parser.error("this RTL checkpoint regression uses exactly 4 products")

    if output.exists():
        shutil.rmtree(output)

    output.mkdir(parents=True)

    product0 = source / "product0"

    for tower in range(2):
        profile_output = output / f"profile{tower}"
        profile_output.mkdir()

        for name in PROFILE_FILES:
            shutil.copy2(
                product0 / f"profile{tower}" / name,
                profile_output / name,
            )

    hashes = []

    for product_index in range(args.products):
        product = source / f"product{product_index}"

        digest_parts = []

        for tower in range(2):
            tower_root = product / f"tower{tower}"
            dma = read_u32le(tower_root / "dma_input.bin", 2 * N)
            expected = read_u32le(
                tower_root / "openfhe_expected.bin",
                N,
            )

            prefix = f"product{product_index}_tower{tower}"

            write_mem(output / f"{prefix}_a.mem", dma[:N])
            write_mem(output / f"{prefix}_b.mem", dma[N:])
            write_mem(output / f"{prefix}_expected.mem", expected)

            digest_parts.extend([
                int(dma[0]),
                int(dma[N]),
                int(expected[0]),
            ])

        hashes.append(digest_parts)

    if len({tuple(item) for item in hashes}) != args.products:
        raise RuntimeError("the four selected products are not distinct")

    metadata = {
        "format": "openfhe-two-tower-prefetch4-v1",
        "product_count": args.products,
        "source": str(source),
    }

    (output / "metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )

    print("PASS: prepared four distinct two-tower OpenFHE products")
    print("PASS: copied one common q0/q1 runtime profile")
    print(f"Output directory: {output}")


if __name__ == "__main__":
    main()
