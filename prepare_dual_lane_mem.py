#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


N = 4096


def read_u32le(
    path: Path,
    expected_words: int,
) -> np.ndarray:
    values = np.fromfile(
        path,
        dtype="<u4",
    )

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(
        values,
        dtype=np.uint32,
    )


def write_mem(
    path: Path,
    values: np.ndarray,
) -> None:
    with path.open(
        "w",
        encoding="utf-8",
        newline="\n",
    ) as output:
        for value in values:
            output.write(
                f"{int(value):08x}\n"
            )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Convert the generated two-tower OpenFHE binary vectors "
            "into readmemh files for the dual-lane RTL regression."
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

    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    for tower_index in range(2):
        tower_directory = (
            vector_root
            / f"tower{tower_index}"
        )

        dma_input = read_u32le(
            tower_directory / "dma_input.bin",
            2 * N,
        )

        expected = read_u32le(
            tower_directory / "openfhe_expected.bin",
            N,
        )

        write_mem(
            output_root / f"tower{tower_index}_a.mem",
            dma_input[:N],
        )

        write_mem(
            output_root / f"tower{tower_index}_b.mem",
            dma_input[N:],
        )

        write_mem(
            output_root / f"tower{tower_index}_expected.mem",
            expected,
        )

    print(
        "PASS: prepared two-tower readmemh vectors"
    )

    print(
        f"Output directory: {output_root}"
    )


if __name__ == "__main__":
    main()
