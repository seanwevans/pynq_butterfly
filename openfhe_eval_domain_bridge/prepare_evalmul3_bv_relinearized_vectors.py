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
            "Create exact paired-tower fused EvalMul3+BV relinearization "
            "simulation vectors from the OpenFHE BV probe."
        )
    )

    parser.add_argument(
        "probe_directory",
        type=Path,
    )

    parser.add_argument(
        "output_directory",
        type=Path,
    )

    parser.add_argument(
        "--coefficients",
        type=int,
        default=32,
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
            f"{path} contains {len(data)} bytes; need {required}"
        )

    return list(
        struct.unpack(
            f"<{count}Q",
            data[:required],
        )
    )


def read_poly(
    root: Path,
    tower_index: int,
    coefficient_count: int,
) -> list[int]:
    return read_u64_words(
        root
        / f"{tower_name(tower_index)}.u64le.bin",
        coefficient_count,
    )


def pack_lanes(lane0: int, lane1: int) -> int:
    for lane in (lane0, lane1):
        if not 0 <= lane < (1 << 32):
            raise ValueError(
                f"value does not fit in 32 bits: {lane}"
            )

    return lane0 | (lane1 << 32)


def write_hex(
    path: Path,
    words: Iterable[int],
) -> int:
    count = 0

    with path.open(
        "w",
        encoding="ascii",
        newline="\n",
    ) as stream:
        for word in words:
            if not 0 <= word < (1 << 64):
                raise ValueError(
                    f"word does not fit in 64 bits: {word}"
                )

            stream.write(f"{word:016x}\n")
            count += 1

    return count


def load_all_towers(
    root: Path,
    tower_count: int,
    coefficient_count: int,
) -> list[list[int]]:
    return [
        read_poly(
            root,
            tower_index,
            coefficient_count,
        )
        for tower_index in range(tower_count)
    ]


def main() -> None:
    args = parse_args()
    metadata = read_json(
        args.probe_directory / "metadata.json"
    )

    if metadata.get("technique") != "BV":
        raise ValueError(
            "fused checkpoint requires BV probe vectors"
        )

    q_towers = int(metadata["q_towers"])
    p_towers = int(metadata["p_towers"])
    digits = int(metadata["digits"])
    digit_towers = int(metadata["digit_towers"])
    eval_key_parts = int(metadata["eval_key_parts"])
    eval_key_towers = int(metadata["eval_key_towers"])
    ring_dimension = int(metadata["ring_dimension"])
    max_q_bits = int(metadata["max_q_modulus_bits"])

    if q_towers % 2:
        raise ValueError(
            "Q tower count must be even"
        )

    if p_towers != 0:
        raise ValueError(
            "BV vectors unexpectedly contain P towers"
        )

    if not (
        digits == eval_key_parts
        and digit_towers == q_towers
        and eval_key_towers == q_towers
    ):
        raise ValueError(
            "BV digit/key dimensions are inconsistent"
        )

    if max_q_bits > 30:
        raise ValueError(
            "current Barrett datapath supports at most 30-bit Q moduli"
        )

    coefficient_count = args.coefficients

    if not 0 < coefficient_count <= ring_dimension:
        raise ValueError(
            "--coefficients is outside the ring"
        )

    profiles = [
        read_json(
            args.probe_directory
            / "profiles_q"
            / f"{tower_name(index)}.json"
        )
        for index in range(q_towers)
    ]

    moduli = [
        int(profile["modulus"])
        for profile in profiles
    ]

    input_a0 = load_all_towers(
        args.probe_directory / "input_a0_q_eval",
        q_towers,
        coefficient_count,
    )

    input_a1 = load_all_towers(
        args.probe_directory / "input_a1_q_eval",
        q_towers,
        coefficient_count,
    )

    input_b0 = load_all_towers(
        args.probe_directory / "input_b0_q_eval",
        q_towers,
        coefficient_count,
    )

    input_b1 = load_all_towers(
        args.probe_directory / "input_b1_q_eval",
        q_towers,
        coefficient_count,
    )

    no_relin_c0 = load_all_towers(
        args.probe_directory / "no_relin_c0_q_eval",
        q_towers,
        coefficient_count,
    )

    no_relin_c1 = load_all_towers(
        args.probe_directory / "no_relin_c1_q_eval",
        q_towers,
        coefficient_count,
    )

    no_relin_c2 = load_all_towers(
        args.probe_directory / "c2_q_eval",
        q_towers,
        coefficient_count,
    )

    relin_c0 = load_all_towers(
        args.probe_directory / "relinearized_c0_q",
        q_towers,
        coefficient_count,
    )

    relin_c1 = load_all_towers(
        args.probe_directory / "relinearized_c1_q",
        q_towers,
        coefficient_count,
    )

    keyswitch_b = load_all_towers(
        args.probe_directory / "keyswitch_q_b",
        q_towers,
        coefficient_count,
    )

    keyswitch_a = load_all_towers(
        args.probe_directory / "keyswitch_q_a",
        q_towers,
        coefficient_count,
    )

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
            load_all_towers(
                digit_root,
                q_towers,
                coefficient_count,
            )
        )

        key_a_data.append(
            load_all_towers(
                key_a_root,
                q_towers,
                coefficient_count,
            )
        )

        key_b_data.append(
            load_all_towers(
                key_b_root,
                q_towers,
                coefficient_count,
            )
        )

    profile_words: list[int] = []
    payload_words: list[int] = []
    expected_words: list[int] = []

    pair_count = q_towers // 2

    for pair_index in range(pair_count):
        tower0 = pair_index * 2
        tower1 = tower0 + 1

        q0 = moduli[tower0]
        q1 = moduli[tower1]

        if not (
            (1 << 29) <= q0 < (1 << 30)
            and (1 << 29) <= q1 < (1 << 30)
        ):
            raise ValueError(
                "unexpected Q modulus width"
            )

        mu0 = BARRETT_SCALE // q0
        mu1 = BARRETT_SCALE // q1

        profile_words.append(
            pack_lanes(q0, q1)
        )

        profile_words.append(
            mu0 | (mu1 << 32)
        )

        for coefficient in range(coefficient_count):
            a0 = [
                input_a0[tower0][coefficient],
                input_a0[tower1][coefficient],
            ]

            a1 = [
                input_a1[tower0][coefficient],
                input_a1[tower1][coefficient],
            ]

            b0 = [
                input_b0[tower0][coefficient],
                input_b0[tower1][coefficient],
            ]

            b1 = [
                input_b1[tower0][coefficient],
                input_b1[tower1][coefficient],
            ]

            calculated_c0 = [
                a0[0] * b0[0] % q0,
                a0[1] * b0[1] % q1,
            ]

            calculated_c1 = [
                (
                    a0[0] * b1[0]
                    + a1[0] * b0[0]
                ) % q0,
                (
                    a0[1] * b1[1]
                    + a1[1] * b0[1]
                ) % q1,
            ]

            calculated_c2 = [
                a1[0] * b1[0] % q0,
                a1[1] * b1[1] % q1,
            ]

            expected_c0 = [
                no_relin_c0[tower0][coefficient],
                no_relin_c0[tower1][coefficient],
            ]

            expected_c1 = [
                no_relin_c1[tower0][coefficient],
                no_relin_c1[tower1][coefficient],
            ]

            expected_c2 = [
                no_relin_c2[tower0][coefficient],
                no_relin_c2[tower1][coefficient],
            ]

            if calculated_c0 != expected_c0:
                raise ValueError(
                    "EvalMul c0 mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            if calculated_c1 != expected_c1:
                raise ValueError(
                    "EvalMul c1 mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            if calculated_c2 != expected_c2:
                raise ValueError(
                    "EvalMul c2 mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            payload_words.extend(
                [
                    pack_lanes(a0[0], a0[1]),
                    pack_lanes(a1[0], a1[1]),
                    pack_lanes(b0[0], b0[1]),
                    pack_lanes(b1[0], b1[1]),
                ]
            )

            calculated_ks_b = [0, 0]
            calculated_ks_a = [0, 0]

            for digit_index in range(digits):
                digit = [
                    digit_data[digit_index][tower0][coefficient],
                    digit_data[digit_index][tower1][coefficient],
                ]

                key_b = [
                    key_b_data[digit_index][tower0][coefficient],
                    key_b_data[digit_index][tower1][coefficient],
                ]

                key_a = [
                    key_a_data[digit_index][tower0][coefficient],
                    key_a_data[digit_index][tower1][coefficient],
                ]

                payload_words.extend(
                    [
                        pack_lanes(digit[0], digit[1]),
                        pack_lanes(key_b[0], key_b[1]),
                        pack_lanes(key_a[0], key_a[1]),
                    ]
                )

                calculated_ks_b[0] = (
                    calculated_ks_b[0]
                    + digit[0] * key_b[0]
                ) % q0

                calculated_ks_b[1] = (
                    calculated_ks_b[1]
                    + digit[1] * key_b[1]
                ) % q1

                calculated_ks_a[0] = (
                    calculated_ks_a[0]
                    + digit[0] * key_a[0]
                ) % q0

                calculated_ks_a[1] = (
                    calculated_ks_a[1]
                    + digit[1] * key_a[1]
                ) % q1

            expected_ks_b = [
                keyswitch_b[tower0][coefficient],
                keyswitch_b[tower1][coefficient],
            ]

            expected_ks_a = [
                keyswitch_a[tower0][coefficient],
                keyswitch_a[tower1][coefficient],
            ]

            if calculated_ks_b != expected_ks_b:
                raise ValueError(
                    "BV ks_b mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            if calculated_ks_a != expected_ks_a:
                raise ValueError(
                    "BV ks_a mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            calculated_relin_c0 = [
                (
                    calculated_c0[0]
                    + calculated_ks_b[0]
                ) % q0,
                (
                    calculated_c0[1]
                    + calculated_ks_b[1]
                ) % q1,
            ]

            calculated_relin_c1 = [
                (
                    calculated_c1[0]
                    + calculated_ks_a[0]
                ) % q0,
                (
                    calculated_c1[1]
                    + calculated_ks_a[1]
                ) % q1,
            ]

            expected_relin_c0 = [
                relin_c0[tower0][coefficient],
                relin_c0[tower1][coefficient],
            ]

            expected_relin_c1 = [
                relin_c1[tower0][coefficient],
                relin_c1[tower1][coefficient],
            ]

            if calculated_relin_c0 != expected_relin_c0:
                raise ValueError(
                    "relinearized c0 mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            if calculated_relin_c1 != expected_relin_c1:
                raise ValueError(
                    "relinearized c1 mismatch at "
                    f"pair={pair_index} coefficient={coefficient}"
                )

            expected_words.extend(
                [
                    pack_lanes(
                        expected_relin_c0[0],
                        expected_relin_c0[1],
                    ),
                    pack_lanes(
                        expected_relin_c1[0],
                        expected_relin_c1[1],
                    ),
                ]
            )

    args.output_directory.mkdir(
        parents=True,
        exist_ok=True,
    )

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

    generated = {
        "format": "openfhe-evalmul3-bv-relinearized-paired-v1",
        "source": str(
            args.probe_directory.resolve()
        ),
        "coefficient_count": coefficient_count,
        "q_towers": q_towers,
        "pair_count": pair_count,
        "digits": digits,
        "ciphertext_count": 1,
        "profile_words": profile_count,
        "payload_words": payload_count,
        "expected_words": expected_count,
        "payload_words_per_coefficient": (
            4 + 3 * digits
        ),
        "payload_words_per_pair": (
            coefficient_count
            * (4 + 3 * digits)
        ),
        "expected_words_per_pair": (
            coefficient_count * 2
        ),
    }

    with (
        args.output_directory / "metadata.json"
    ).open(
        "w",
        encoding="utf-8",
        newline="\n",
    ) as stream:
        json.dump(
            generated,
            stream,
            indent=2,
        )

        stream.write("\n")

    print(
        "PASS: exact fused EvalMul3 + BV arithmetic "
        "reproduces OpenFHE relinearized ciphertext components"
    )

    print(f"pair_count={pair_count}")
    print(f"digits={digits}")
    print(f"coefficient_count={coefficient_count}")
    print(f"profile_words={profile_count}")
    print(f"payload_words={payload_count}")
    print(f"expected_words={expected_count}")
    print(
        "output_directory="
        f"{args.output_directory.resolve()}"
    )


if __name__ == "__main__":
    main()
