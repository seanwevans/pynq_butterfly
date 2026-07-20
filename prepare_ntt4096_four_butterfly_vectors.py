#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


N = 4096
TWIDDLE_WORDS = N - 1


def read_mem(path: Path) -> np.ndarray:
    values = [
        int(line.strip(), 16)
        for line in path.read_text(
            encoding="utf-8"
        ).splitlines()
        if line.strip()
    ]

    if len(values) < TWIDDLE_WORDS:
        raise ValueError(
            f"{path}: found {len(values)} words; "
            f"expected at least {TWIDDLE_WORDS}"
        )

    return np.asarray(
        values[:TWIDDLE_WORDS],
        dtype=np.uint64,
    )


def write_mem(
    path: Path,
    values: np.ndarray,
) -> None:
    path.write_text(
        "".join(
            f"{int(value):08x}\n"
            for value in values
        ),
        encoding="utf-8",
    )


def forward_dif(
    values: np.ndarray,
    twiddles: np.ndarray,
    modulus: int,
) -> np.ndarray:
    result = [
        int(value)
        for value in values
    ]

    for stage in range(11, -1, -1):
        distance = 1 << stage
        stage_base = distance - 1
        block_width = distance << 1

        for block in range(0, N, block_width):
            for offset in range(distance):
                address_a = block + offset
                address_b = address_a + distance

                value_a = result[address_a]
                value_b = result[address_b]
                omega = int(
                    twiddles[stage_base + offset]
                )

                result[address_a] = (
                    value_a + value_b
                ) % modulus

                result[address_b] = (
                    (value_a - value_b)
                    * omega
                ) % modulus

    return np.asarray(
        result,
        dtype=np.uint64,
    )


def inverse_dit(
    values: np.ndarray,
    twiddles: np.ndarray,
    modulus: int,
) -> np.ndarray:
    result = [
        int(value)
        for value in values
    ]

    for stage in range(12):
        distance = 1 << stage
        stage_base = distance - 1
        block_width = distance << 1

        for block in range(0, N, block_width):
            for offset in range(distance):
                address_a = block + offset
                address_b = address_a + distance

                value_a = result[address_a]
                value_b = result[address_b]
                omega = int(
                    twiddles[stage_base + offset]
                )

                product = (
                    value_b * omega
                ) % modulus

                result[address_a] = (
                    value_a + product
                ) % modulus

                result[address_b] = (
                    value_a - product
                ) % modulus

    return np.asarray(
        result,
        dtype=np.uint64,
    )


def prepare_tower(
    profile_directory: Path,
    output_directory: Path,
    tower_index: int,
    seed: int,
) -> dict[str, int]:
    metadata = json.loads(
        (
            profile_directory
            / "profile.json"
        ).read_text(
            encoding="utf-8"
        )
    )

    modulus = int(metadata["modulus"])

    forward_twiddles = read_mem(
        profile_directory
        / "forward_twiddles.mem"
    )

    inverse_twiddles = read_mem(
        profile_directory
        / "inverse_twiddles.mem"
    )

    generator = np.random.default_rng(seed)

    input_values = generator.integers(
        low=0,
        high=modulus,
        size=N,
        dtype=np.uint64,
    )

    forward_expected = forward_dif(
        input_values,
        forward_twiddles,
        modulus,
    )

    roundtrip_expected = (
        input_values
        * np.uint64(N)
    ) % np.uint64(modulus)

    inverse_result = inverse_dit(
        forward_expected,
        inverse_twiddles,
        modulus,
    )

    if not np.array_equal(
        inverse_result,
        roundtrip_expected,
    ):
        mismatch = int(
            np.flatnonzero(
                inverse_result
                != roundtrip_expected
            )[0]
        )

        raise AssertionError(
            f"tower {tower_index}: reference round trip "
            f"failed at coefficient {mismatch}"
        )

    prefix = f"q{tower_index}"

    write_mem(
        output_directory
        / f"{prefix}_input.mem",
        input_values,
    )

    write_mem(
        output_directory
        / f"{prefix}_forward_twiddles.mem",
        forward_twiddles,
    )

    write_mem(
        output_directory
        / f"{prefix}_inverse_twiddles.mem",
        inverse_twiddles,
    )

    write_mem(
        output_directory
        / f"{prefix}_forward_expected.mem",
        forward_expected,
    )

    write_mem(
        output_directory
        / f"{prefix}_roundtrip_expected.mem",
        roundtrip_expected,
    )

    return {
        "tower_index": tower_index,
        "modulus": modulus,
        "seed": seed,
        "coefficient_count": N,
        "twiddle_words": TWIDDLE_WORDS,
    }


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help=(
            "Product directory containing profile0 "
            "and profile1"
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        required=True,
    )

    args = parser.parse_args()

    input_root = args.input.resolve()
    output_root = args.output.resolve()

    output_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    towers = [
        prepare_tower(
            input_root / "profile0",
            output_root,
            tower_index=0,
            seed=0x409600,
        ),
        prepare_tower(
            input_root / "profile1",
            output_root,
            tower_index=1,
            seed=0x409601,
        ),
    ]

    (
        output_root
        / "metadata.json"
    ).write_text(
        json.dumps(
            {
                "n": N,
                "transform": (
                    "forward DIF followed by "
                    "unscaled inverse DIT"
                ),
                "expected_transform_cycles": 141_313,
                "expected_butterflies": 24_576,
                "towers": towers,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(
        "PASS: prepared q0 and q1 "
        "four-butterfly NTT vectors"
    )

    print(
        "PASS: software forward DIF and inverse DIT "
        "round trips are exact"
    )

    print(
        f"Output directory: {output_root}"
    )


if __name__ == "__main__":
    main()
