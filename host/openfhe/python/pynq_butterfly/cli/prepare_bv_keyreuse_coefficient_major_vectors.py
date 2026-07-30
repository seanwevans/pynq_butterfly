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
            "Create exact coefficient-major evaluation-key-reuse vectors "
            "from the OpenFHE BV relinearization probe."
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

    parser.add_argument(
        "--ciphertexts",
        type=int,
        default=8,
    )

    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(
        path.read_text(
            encoding="utf-8",
        )
    )


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def digit_name(index: int) -> str:
    return f"digit{index:03d}"


def read_u64_words(
    path: Path,
    count: int,
) -> list[int]:
    data = path.read_bytes()
    required = count * 8

    if len(data) < required:
        raise ValueError(
            f"{path} contains {len(data)} bytes; "
            f"need {required}"
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


def pack_lanes(
    lane0: int,
    lane1: int,
) -> int:
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


def main() -> None:
    args = parse_args()

    if args.ciphertexts < 8:
        raise ValueError(
            "--ciphertexts must be at least 8"
        )

    metadata = read_json(
        args.probe_directory
        / "metadata.json"
    )

    if metadata.get("technique") != "BV":
        raise ValueError(
            "coefficient-major checkpoint requires BV vectors"
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
            "BV digit/evaluation-key dimensions are inconsistent"
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

    digit_data: list[list[list[int]]] = []
    key_a_data: list[list[list[int]]] = []
    key_b_data: list[list[list[int]]] = []

    for digit_index in range(digits):
        digit_data.append(
            load_all_towers(
                args.probe_directory
                / "digits"
                / digit_name(digit_index),
                q_towers,
                coefficient_count,
            )
        )

        key_a_data.append(
            load_all_towers(
                args.probe_directory
                / "eval_key_a"
                / digit_name(digit_index),
                q_towers,
                coefficient_count,
            )
        )

        key_b_data.append(
            load_all_towers(
                args.probe_directory
                / "eval_key_b"
                / digit_name(digit_index),
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

        mu0 = BARRETT_SCALE // q0
        mu1 = BARRETT_SCALE // q1

        profile_words.extend(
            [
                pack_lanes(q0, q1),
                mu0 | (mu1 << 32),
            ]
        )

        for coefficient in range(coefficient_count):
            a0_word = pack_lanes(
                input_a0[tower0][coefficient],
                input_a0[tower1][coefficient],
            )

            a1_word = pack_lanes(
                input_a1[tower0][coefficient],
                input_a1[tower1][coefficient],
            )

            b0_word = pack_lanes(
                input_b0[tower0][coefficient],
                input_b0[tower1][coefficient],
            )

            b1_word = pack_lanes(
                input_b1[tower0][coefficient],
                input_b1[tower1][coefficient],
            )

            for _ in range(args.ciphertexts):
                payload_words.extend(
                    [
                        a0_word,
                        a1_word,
                        b0_word,
                        b1_word,
                    ]
                )

            for digit_index in range(digits):
                key_b_word = pack_lanes(
                    key_b_data[digit_index][tower0][coefficient],
                    key_b_data[digit_index][tower1][coefficient],
                )

                key_a_word = pack_lanes(
                    key_a_data[digit_index][tower0][coefficient],
                    key_a_data[digit_index][tower1][coefficient],
                )

                digit_word = pack_lanes(
                    digit_data[digit_index][tower0][coefficient],
                    digit_data[digit_index][tower1][coefficient],
                )

                payload_words.extend(
                    [
                        key_b_word,
                        key_a_word,
                    ]
                )

                for _ in range(args.ciphertexts):
                    payload_words.append(
                        digit_word
                    )

            expected_c0 = pack_lanes(
                relin_c0[tower0][coefficient],
                relin_c0[tower1][coefficient],
            )

            expected_c1 = pack_lanes(
                relin_c1[tower0][coefficient],
                relin_c1[tower1][coefficient],
            )

            for _ in range(args.ciphertexts):
                expected_words.extend(
                    [
                        expected_c0,
                        expected_c1,
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

    words_per_coefficient = (
        4 * args.ciphertexts
        + digits * (
            2 + args.ciphertexts
        )
    )

    legacy_words_per_coefficient = (
        args.ciphertexts
        * (
            4 + 3 * digits
        )
    )

    generated = {
        "format": "openfhe-bv-keyreuse-coefficient-major-v1",
        "source": str(
            args.probe_directory.resolve()
        ),
        "coefficient_count": coefficient_count,
        "q_towers": q_towers,
        "pair_count": pair_count,
        "digits": digits,
        "ciphertext_count": args.ciphertexts,
        "profile_words": profile_count,
        "payload_words": payload_count,
        "expected_words": expected_count,
        "words_per_coefficient_per_pair": words_per_coefficient,
        "legacy_words_per_coefficient_per_pair": legacy_words_per_coefficient,
        "input_reduction": (
            1.0
            - words_per_coefficient
            / legacy_words_per_coefficient
        ),
    }

    (
        args.output_directory
        / "metadata.json"
    ).write_text(
        json.dumps(
            generated,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )

    print(
        "PASS: generated exact coefficient-major "
        "evaluation-key-reuse vectors"
    )

    print(f"pair_count={pair_count}")
    print(f"digits={digits}")
    print(f"ciphertexts={args.ciphertexts}")
    print(f"coefficient_count={coefficient_count}")
    print(
        "words_per_coefficient_per_pair="
        f"{words_per_coefficient}"
    )
    print(
        "legacy_words_per_coefficient_per_pair="
        f"{legacy_words_per_coefficient}"
    )
    print(
        "input_reduction="
        f"{generated['input_reduction']:.4%}"
    )
    print(f"profile_words={profile_count}")
    print(f"payload_words={payload_count}")
    print(f"expected_words={expected_count}")
    print(
        "output_directory="
        f"{args.output_directory.resolve()}"
    )


if __name__ == "__main__":
    main()
