#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
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


def generate_product(
    bridge: Path,
    destination: Path,
    seed: int,
) -> None:
    subprocess.run(
        [
            str(bridge),
            "generate",
            str(destination),
            str(seed),
        ],
        check=True,
    )


def require_matching_profiles(
    first: Path,
    second: Path,
) -> None:
    for tower_index in range(2):
        for filename in PROFILE_FILES:
            first_path = first / f"profile{tower_index}" / filename
            second_path = second / f"profile{tower_index}" / filename

            if first_path.read_bytes() != second_path.read_bytes():
                raise RuntimeError(
                    "Generated products do not share the same runtime "
                    f"profile: {first_path} != {second_path}"
                )


def export_mem_files(
    product_directory: Path,
    output_root: Path,
    product_index: int,
) -> None:
    for tower_index in range(2):
        tower_directory = product_directory / f"tower{tower_index}"

        dma_input = read_u32le(
            tower_directory / "dma_input.bin",
            2 * N,
        )

        expected = read_u32le(
            tower_directory / "openfhe_expected.bin",
            N,
        )

        prefix = f"product{product_index}_tower{tower_index}"

        write_mem(
            output_root / f"{prefix}_a.mem",
            dma_input[:N],
        )

        write_mem(
            output_root / f"{prefix}_b.mem",
            dma_input[N:],
        )

        write_mem(
            output_root / f"{prefix}_expected.mem",
            expected,
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Generate two distinct OpenFHE DCRTPoly products and "
            "convert them to readmemh files for the batch-of-two "
            "AXI regression."
        )
    )

    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed0", type=int, default=202947043366)
    parser.add_argument("--seed1", type=int, default=202947043367)

    args = parser.parse_args()

    if args.seed0 == args.seed1:
        parser.error("--seed0 and --seed1 must differ")

    bridge = args.bridge.resolve()
    output_root = args.output.resolve()

    if not bridge.is_file():
        raise FileNotFoundError(
            f"OpenFHE bridge executable not found: {bridge}"
        )

    if output_root.exists():
        shutil.rmtree(output_root)

    output_root.mkdir(parents=True)

    product0 = output_root / "product0"
    product1 = output_root / "product1"

    generate_product(bridge, product0, args.seed0)
    generate_product(bridge, product1, args.seed1)

    require_matching_profiles(product0, product1)

    export_mem_files(product0, output_root, 0)
    export_mem_files(product1, output_root, 1)

    metadata = {
        "format": "openfhe-two-tower-batch2-v1",
        "batch_count": 2,
        "seeds": [args.seed0, args.seed1],
        "products": ["product0", "product1"],
    }

    (output_root / "batch2_metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    print("PASS: generated two distinct OpenFHE DCRTPoly products")
    print("PASS: q0/q1 runtime profiles are identical across the batch")
    print("PASS: prepared batch-of-two readmemh vectors")
    print(f"Seed 0: {args.seed0}")
    print(f"Seed 1: {args.seed1}")
    print(f"Output directory: {output_root}")


if __name__ == "__main__":
    main()
