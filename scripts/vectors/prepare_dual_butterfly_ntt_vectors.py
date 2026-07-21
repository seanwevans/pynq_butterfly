#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


N = 4096
LOG_N = 12
COMPACT_TWIDDLES = N - 1


def read_mem(path: Path, expected_words: int) -> np.ndarray:
    values = [
        int(line.strip(), 16)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

    if len(values) != expected_words:
        raise ValueError(
            f"{path}: found {len(values)} words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint64)


def read_u32le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return values.astype(np.uint64)


def write_mem(path: Path, values: np.ndarray) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as output:
        for value in values:
            output.write(f"{int(value):08x}\n")


def forward_dif(
    coefficients: np.ndarray,
    twiddles: np.ndarray,
    modulus: int,
) -> np.ndarray:
    values = coefficients.astype(np.uint64, copy=True)

    for stage in range(LOG_N - 1, -1, -1):
        half = 1 << stage
        span = half << 1
        stage_base = half - 1

        for group_base in range(0, N, span):
            for j in range(half):
                left = group_base + j
                right = left + half

                a = int(values[left])
                b = int(values[right])

                values[left] = (a + b) % modulus
                values[right] = (
                    ((a - b) % modulus)
                    * int(twiddles[stage_base + j])
                ) % modulus

    return values


def inverse_dit_unscaled(
    coefficients: np.ndarray,
    twiddles: np.ndarray,
    modulus: int,
) -> np.ndarray:
    values = coefficients.astype(np.uint64, copy=True)

    for stage in range(LOG_N):
        half = 1 << stage
        span = half << 1
        stage_base = half - 1

        for group_base in range(0, N, span):
            for j in range(half):
                left = group_base + j
                right = left + half

                a = int(values[left])
                product = (
                    int(values[right])
                    * int(twiddles[stage_base + j])
                ) % modulus

                values[left] = (a + product) % modulus
                values[right] = (a - product) % modulus

    return values


def prepare_tower(
    vector_root: Path,
    output_root: Path,
    tower_index: int,
) -> None:
    profile_root = vector_root / f"profile{tower_index}"
    tower_root = vector_root / f"tower{tower_index}"

    metadata = json.loads(
        (profile_root / "profile.json").read_text(encoding="utf-8")
    )

    modulus = int(metadata["modulus"])

    forward_twiddles = read_mem(
        profile_root / "forward_twiddles.mem",
        COMPACT_TWIDDLES,
    )

    inverse_twiddles = read_mem(
        profile_root / "inverse_twiddles.mem",
        COMPACT_TWIDDLES,
    )

    dma_input = read_u32le(
        tower_root / "dma_input.bin",
        2 * N,
    )

    coefficients = dma_input[:N]

    forward_expected = forward_dif(
        coefficients,
        forward_twiddles,
        modulus,
    )

    inverse_expected = inverse_dit_unscaled(
        forward_expected,
        inverse_twiddles,
        modulus,
    )

    scaled_original = (
        coefficients
        * np.uint64(N)
    ) % np.uint64(modulus)

    if not np.array_equal(inverse_expected, scaled_original):
        mismatch = int(
            np.flatnonzero(inverse_expected != scaled_original)[0]
        )

        raise AssertionError(
            f"tower {tower_index}: inverse round trip mismatch at "
            f"coefficient {mismatch}"
        )

    write_mem(
        output_root / f"tower{tower_index}_input.mem",
        coefficients,
    )

    write_mem(
        output_root / f"tower{tower_index}_forward_expected.mem",
        forward_expected,
    )

    write_mem(
        output_root / f"tower{tower_index}_inverse_expected.mem",
        inverse_expected,
    )

    print(
        f"PASS: prepared q{tower_index} forward DIF and inverse DIT vectors"
    )

    print(
        f"q{tower_index} modulus: {modulus}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare q0 and q1 golden transform vectors for the "
            "runtime-profile two-butterfly N=4096 RTL checkpoint."
        )
    )

    parser.add_argument(
        "--vectors",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
    )

    args = parser.parse_args()

    vector_root = args.vectors.resolve()
    output_root = args.output.resolve()

    output_root.mkdir(parents=True, exist_ok=True)

    prepare_tower(vector_root, output_root, 0)
    prepare_tower(vector_root, output_root, 1)

    print(
        "PASS: inverse outputs equal N times the original coefficients"
    )

    print(
        f"Output directory: {output_root}"
    )


if __name__ == "__main__":
    main()
