#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Iterable


BARRETT_SCALE = 1 << 60


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert exact OpenFHE BV relinearization probe vectors into "
            "paired-tower BVKM simulation frames."
        )
    )

    parser.add_argument(
        "probe_directory",
        type=Path,
        help="OpenFHE relin_bv_t12_d0 vector directory",
    )

    parser.add_argument(
        "output_directory",
        type=Path,
        help="directory for profiles.hex, payload.hex, and expected.hex",
    )

    parser.add_argument(
        "--coefficients",
        type=int,
        default=32,
        help="number of leading evaluation-domain coefficients to test",
    )

    return parser.parse_args()


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def digit_name(index: int) -> str:
    return f"digit{index:03d}"


def read_u64_words(path: Path, count: int) -> list[int]:
    data = path.read_bytes()
    required = count * 8

    if len(data) < required:
        raise ValueError(
            f"{path} contains {len(data)} bytes; need at least {required}"
        )

    return list(struct.unpack(f"<{count}Q", data[:required]))


def poly_tower(
    root: Path,
    tower_index: int,
    coefficient_count: int,
) -> list[int]:
    return read_u64_words(
        root / f"{tower_name(tower_index)}.u64le.bin",
        coefficient_count,
    )


def write_hex(path: Path, words: Iterable[int]) -> int:
    count = 0

    with path.open("w", encoding="ascii", newline="\n") as stream:
        for value in words:
            if not 0 <= value < (1 << 64):
                raise ValueError(f"word does not fit in 64 bits: {value}")

            stream.write(f"{value:016x}\n")
            count += 1

    return count


def pack_lanes(lane0: int, lane1: int) -> int:
    for lane in (lane0, lane1):
        if not 0 <= lane < (1 << 32):
            raise ValueError(f"tower value does not fit in 32 bits: {lane}")

    return lane0 | (lane1 << 32)


def main() -> None:
    args = parse_args()

    metadata = read_json(args.probe_directory / "metadata.json")

    if metadata.get("technique") != "BV":
        raise ValueError("probe metadata is not BV")

    q_towers = int(metadata["q_towers"])
    p_towers = int(metadata["p_towers"])
    digits = int(metadata["digits"])
    digit_towers = int(metadata["digit_towers"])
    eval_key_parts = int(metadata["eval_key_parts"])
    eval_key_towers = int(metadata["eval_key_towers"])
    ring_dimension = int(metadata["ring_dimension"])
    max_q_bits = int(metadata["max_q_modulus_bits"])

    if q_towers % 2:
        raise ValueError("paired-tower test requires an even Q tower count")

    if p_towers != 0:
        raise ValueError("BV checkpoint unexpectedly contains P towers")

    if not (
        digits == eval_key_parts
        and digit_towers == q_towers
        and eval_key_towers == q_towers
    ):
        raise ValueError("BV digit/evaluation-key dimensions are inconsistent")

    if max_q_bits > 30:
        raise ValueError(
            f"current Barrett core supports at most 30-bit Q moduli, got {max_q_bits}"
        )

    coefficient_count = args.coefficients

    if coefficient_count <= 0:
        raise ValueError("--coefficients must be positive")

    if coefficient_count > ring_dimension:
        raise ValueError(
            f"requested {coefficient_count} coefficients; ring has {ring_dimension}"
        )

    profiles = [
        read_json(
            args.probe_directory
            / "profiles_q"
            / f"{tower_name(index)}.json"
        )
        for index in range(q_towers)
    ]

    moduli = [int(profile["modulus"]) for profile in profiles]

    for modulus in moduli:
        if not (1 << 29) <= modulus < (1 << 30):
            raise ValueError(f"unexpected Q modulus: {modulus}")

    digit_data: list[list[list[int]]] = []
    key_a_data: list[list[list[int]]] = []
    key_b_data: list[list[list[int]]] = []

    for digit_index in range(digits):
        digit_root = (
            args.probe_directory
            / "digits"
            / digit_name(digit_index)
        )

        key_a_root = (
            args.probe_directory
            / "eval_key_a"
            / digit_name(digit_index)
        )

        key_b_root = (
            args.probe_directory
            / "eval_key_b"
            / digit_name(digit_index)
        )

        digit_data.append(
            [
                poly_tower(
                    digit_root,
                    tower_index,
                    coefficient_count,
                )
                for tower_index in range(q_towers)
            ]
        )

        key_a_data.append(
            [
                poly_tower(
                    key_a_root,
                    tower_index,
                    coefficient_count,
                )
                for tower_index in range(q_towers)
            ]
        )

        key_b_data.append(
            [
                poly_tower(
                    key_b_root,
                    tower_index,
                    coefficient_count,
                )
                for tower_index in range(q_towers)
            ]
        )

    expected_a = [
        poly_tower(
            args.probe_directory / "keyswitch_q_a",
            tower_index,
            coefficient_count,
        )
        for tower_index in range(q_towers)
    ]

    expected_b = [
        poly_tower(
            args.probe_directory / "keyswitch_q_b",
            tower_index,
            coefficient_count,
        )
        for tower_index in range(q_towers)
    ]

    profile_words: list[int] = []
    payload_words: list[int] = []
    expected_words: list[int] = []

    pair_count = q_towers // 2

    for pair_index in range(pair_count):
        tower0 = pair_index * 2
        tower1 = tower0 + 1

        q0 = moduli[tower0]
        q1 = moduli[tower1]

        mu0 = BARRETT_SCALE // q0
        mu1 = BARRETT_SCALE // q1

        if mu0 >= (1 << 31) or mu1 >= (1 << 31):
            raise ValueError("Barrett reciprocal does not fit in 31 bits")

        profile_words.append(pack_lanes(q0, q1))
        profile_words.append(mu0 | (mu1 << 32))

        for coefficient in range(coefficient_count):
            calculated_b = [0, 0]
            calculated_a = [0, 0]

            for digit_index in range(digits):
                digit0 = digit_data[digit_index][tower0][coefficient]
                digit1 = digit_data[digit_index][tower1][coefficient]

                key_b0 = key_b_data[digit_index][tower0][coefficient]
                key_b1 = key_b_data[digit_index][tower1][coefficient]

                key_a0 = key_a_data[digit_index][tower0][coefficient]
                key_a1 = key_a_data[digit_index][tower1][coefficient]

                payload_words.append(pack_lanes(digit0, digit1))
                payload_words.append(pack_lanes(key_b0, key_b1))
                payload_words.append(pack_lanes(key_a0, key_a1))

                calculated_b[0] = (
                    calculated_b[0] + digit0 * key_b0
                ) % q0

                calculated_b[1] = (
                    calculated_b[1] + digit1 * key_b1
                ) % q1

                calculated_a[0] = (
                    calculated_a[0] + digit0 * key_a0
                ) % q0

                calculated_a[1] = (
                    calculated_a[1] + digit1 * key_a1
                ) % q1

            expected_b0 = expected_b[tower0][coefficient]
            expected_b1 = expected_b[tower1][coefficient]
            expected_a0 = expected_a[tower0][coefficient]
            expected_a1 = expected_a[tower1][coefficient]

            if calculated_b != [expected_b0, expected_b1]:
                raise ValueError(
                    "OpenFHE BV B contribution mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            if calculated_a != [expected_a0, expected_a1]:
                raise ValueError(
                    "OpenFHE BV A contribution mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            expected_words.append(pack_lanes(expected_b0, expected_b1))
            expected_words.append(pack_lanes(expected_a0, expected_a1))

    args.output_directory.mkdir(parents=True, exist_ok=True)

    profile_count = write_hex(
        args.output_directory / "profiles.hex",
        profile_words,
    )

    payload_count = write_hex(
        args.output_directory / "payload.hex",
        payload_words,
    )

    expected_count = write_hex(
        args.output_directory / "expected.hex",
        expected_words,
    )

    generated_metadata = {
        "format": "openfhe-bv-keyswitch-mac-paired-v1",
        "source": str(args.probe_directory.resolve()),
        "ring_dimension_source": ring_dimension,
        "coefficient_count": coefficient_count,
        "q_towers": q_towers,
        "pair_count": pair_count,
        "digits": digits,
        "ciphertext_count": 1,
        "profile_words": profile_count,
        "payload_words": payload_count,
        "expected_words": expected_count,
        "payload_words_per_pair": coefficient_count * digits * 3,
        "expected_words_per_pair": coefficient_count * 2,
    }

    with (
        args.output_directory / "metadata.json"
    ).open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(generated_metadata, stream, indent=2)
        stream.write("\n")

    print(
        "PASS: exact BV digit/key products reproduce "
        "OpenFHE KeySwitchCore contributions"
    )
    print(f"pair_count={pair_count}")
    print(f"digits={digits}")
    print(f"coefficient_count={coefficient_count}")
    print(f"profile_words={profile_count}")
    print(f"payload_words={payload_count}")
    print(f"expected_words={expected_count}")
    print(f"output_directory={args.output_directory.resolve()}")


if __name__ == "__main__":
    main()
