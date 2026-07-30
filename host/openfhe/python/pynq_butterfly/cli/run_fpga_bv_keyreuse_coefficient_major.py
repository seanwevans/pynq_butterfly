#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import numpy as np
from pynq import Overlay, allocate


N = 4096

PROFILE_COMMAND = np.uint32(0x524C5046)  # RLPF
BATCH_COMMAND = np.uint32(0x524C434D)    # RLCM

DIGIT_COUNT_EXPECTED = 12
PAIR_COUNT_EXPECTED = 6
MAX_BATCH = 64

CLOCK_HZ = 100_000_000
DMA_LENGTH_WIDTH = 26
MAX_DMA_BYTES = (1 << DMA_LENGTH_WIDTH) - 1

EVAL_WORDS_PER_CIPHERTEXT = 4
KEY_WORDS_PER_DIGIT = 2
DIGIT_WORDS_PER_CIPHERTEXT = 1
OUTPUT_WORDS_PER_CIPHERTEXT = 2

# The first coefficient-major core drains the multiplier pipelines and then
# serializes 2*B output words before accepting the next coefficient.
ESTIMATED_DRAIN_CYCLES = 8


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def digit_name(index: int) -> str:
    return f"digit{index:03d}"


def read_u64le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(
        path,
        dtype="<u8",
        count=expected_words,
    )

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint64)


def read_tower_u32(
    root: Path,
    tower_index: int,
) -> np.ndarray:
    values = read_u64le(
        root / f"{tower_name(tower_index)}.u64le.bin",
        N,
    )

    if np.any(values > np.uint64(0xFFFFFFFF)):
        bad = int(
            np.flatnonzero(
                values > np.uint64(0xFFFFFFFF)
            )[0]
        )

        raise ValueError(
            f"{root}: tower {tower_index}, coefficient {bad} "
            "does not fit in 32 bits"
        )

    return values.astype(np.uint32)


def pair_words(
    lane0: np.ndarray,
    lane1: np.ndarray,
) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError(
            "paired tower arrays have different shapes"
        )

    return (
        lane0.astype(np.uint64)
        | (
            lane1.astype(np.uint64)
            << np.uint64(32)
        )
    )


def split_words(
    paired: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(
        paired,
        dtype=np.uint64,
    )

    return (
        (
            values
            & np.uint64(0xFFFFFFFF)
        ).astype(np.uint32),
        np.right_shift(
            values,
            np.uint64(32),
        ).astype(np.uint32),
    )


def require_aligned_buffer(
    buffer,
    label: str,
    alignment: int = 8,
) -> None:
    address = int(
        getattr(
            buffer,
            "device_address",
            buffer.physical_address,
        )
    )

    if address % alignment != 0:
        raise RuntimeError(
            f"{label} device address 0x{address:x} "
            f"is not {alignment}-byte aligned"
        )

    if int(buffer.nbytes) % alignment != 0:
        raise RuntimeError(
            f"{label} length {buffer.nbytes} "
            f"is not a multiple of {alignment} bytes"
        )


def resolve_dma(overlay: Overlay):
    matches: list[str] = []

    for name, metadata in overlay.ip_dict.items():
        ip_type = str(
            metadata.get("type", "")
        ).lower()

        if (
            name.lower() == "dma"
            or "axi_dma" in ip_type
        ):
            matches.append(name)

    if len(matches) != 1:
        inventory = [
            (
                name,
                metadata.get("type", ""),
            )
            for name, metadata
            in overlay.ip_dict.items()
        ]

        raise RuntimeError(
            "Expected exactly one AXI DMA; "
            f"matches={matches}, inventory={inventory}"
        )

    return getattr(
        overlay,
        matches[0],
    )


def send_only(
    dma,
    buffer,
) -> float:
    buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()

    return (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0


def run_frame(
    dma,
    send_buffer,
    receive_buffer,
) -> float:
    receive_buffer[:] = 0

    send_buffer.flush()
    receive_buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.recvchannel.transfer(
        receive_buffer
    )

    dma.sendchannel.transfer(
        send_buffer
    )

    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_us = (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0

    receive_buffer.invalidate()

    return elapsed_us


def load_profile(
    vector_root: Path,
    tower_index: int,
) -> tuple[int, int]:
    metadata = read_json(
        vector_root
        / "profiles_q"
        / f"{tower_name(tower_index)}.json"
    )

    modulus = int(metadata["modulus"])
    mu = (1 << 60) // modulus

    if not (
        (1 << 29) < modulus < (1 << 30)
    ):
        raise ValueError(
            f"tower {tower_index}: modulus {modulus} "
            "is outside 2^29 < q < 2^30"
        )

    if mu >= (1 << 31):
        raise ValueError(
            f"tower {tower_index}: Barrett reciprocal "
            "does not fit in 31 bits"
        )

    return modulus, mu


def build_profile_frame(
    vector_root: Path,
    tower0: int,
    tower1: int,
) -> np.ndarray:
    modulus0, mu0 = load_profile(
        vector_root,
        tower0,
    )

    modulus1, mu1 = load_profile(
        vector_root,
        tower1,
    )

    command_word = (
        np.uint64(PROFILE_COMMAND)
        | (
            np.uint64(PROFILE_COMMAND)
            << np.uint64(32)
        )
    )

    return np.asarray(
        [
            command_word,
            (
                np.uint64(modulus0)
                | (
                    np.uint64(modulus1)
                    << np.uint64(32)
                )
            ),
            (
                np.uint64(mu0)
                | (
                    np.uint64(mu1)
                    << np.uint64(32)
                )
            ),
        ],
        dtype=np.uint64,
    )


def load_pair_data(
    vector_root: Path,
    tower0: int,
    tower1: int,
    digit_count: int,
) -> dict[str, object]:
    def paired(root: Path) -> np.ndarray:
        return pair_words(
            read_tower_u32(
                root,
                tower0,
            ),
            read_tower_u32(
                root,
                tower1,
            ),
        )

    inputs = {
        "a0": paired(
            vector_root / "input_a0_q_eval"
        ),
        "a1": paired(
            vector_root / "input_a1_q_eval"
        ),
        "b0": paired(
            vector_root / "input_b0_q_eval"
        ),
        "b1": paired(
            vector_root / "input_b1_q_eval"
        ),
    }

    digits: list[np.ndarray] = []
    key_b: list[np.ndarray] = []
    key_a: list[np.ndarray] = []

    for digit_index in range(digit_count):
        digit_dir = digit_name(digit_index)

        digits.append(
            paired(
                vector_root
                / "digits"
                / digit_dir
            )
        )

        key_b.append(
            paired(
                vector_root
                / "eval_key_b"
                / digit_dir
            )
        )

        key_a.append(
            paired(
                vector_root
                / "eval_key_a"
                / digit_dir
            )
        )

    expected = np.empty(
        (
            N,
            OUTPUT_WORDS_PER_CIPHERTEXT,
        ),
        dtype=np.uint64,
    )

    expected[:, 0] = paired(
        vector_root / "relinearized_c0_q"
    )

    expected[:, 1] = paired(
        vector_root / "relinearized_c1_q"
    )

    return {
        "inputs": inputs,
        "digits": digits,
        "key_b": key_b,
        "key_a": key_a,
        "expected": expected,
    }


def fill_coefficient_major_frame(
    send_buffer,
    pair_data: dict[str, object],
    ciphertext_count: int,
    digit_count: int,
) -> None:
    command_word = (
        np.uint64(BATCH_COMMAND)
        | (
            np.uint64(BATCH_COMMAND)
            << np.uint64(32)
        )
    )

    header_word = (
        np.uint64(ciphertext_count)
        | (
            np.uint64(digit_count)
            << np.uint64(32)
        )
    )

    send_buffer[0] = command_word
    send_buffer[1] = header_word

    inputs = pair_data["inputs"]
    digits = pair_data["digits"]
    key_b = pair_data["key_b"]
    key_a = pair_data["key_a"]

    offset = 2

    for coefficient in range(N):
        for _ in range(ciphertext_count):
            send_buffer[offset] = inputs["a0"][coefficient]
            send_buffer[offset + 1] = inputs["a1"][coefficient]
            send_buffer[offset + 2] = inputs["b0"][coefficient]
            send_buffer[offset + 3] = inputs["b1"][coefficient]
            offset += EVAL_WORDS_PER_CIPHERTEXT

        for digit_index in range(digit_count):
            send_buffer[offset] = key_b[digit_index][coefficient]
            send_buffer[offset + 1] = key_a[digit_index][coefficient]
            offset += KEY_WORDS_PER_DIGIT

            digit_word = digits[digit_index][coefficient]

            send_buffer[
                offset:offset + ciphertext_count
            ] = digit_word

            offset += ciphertext_count

    if offset != int(send_buffer.size):
        raise RuntimeError(
            f"RLCM frame filled {offset} words; "
            f"expected {send_buffer.size}"
        )


def validate_pair(
    receive_buffer,
    expected: np.ndarray,
    ciphertext_count: int,
    pair_index: int,
) -> None:
    actual = np.asarray(
        receive_buffer,
        dtype=np.uint64,
    ).reshape(
        N,
        ciphertext_count,
        OUTPUT_WORDS_PER_CIPHERTEXT,
    )

    expected_view = expected[
        :,
        np.newaxis,
        :,
    ]

    mismatches = (
        actual
        != expected_view
    )

    if not np.any(mismatches):
        return

    coefficient, ciphertext, component = np.argwhere(
        mismatches
    )[0]

    raise AssertionError(
        f"pair {pair_index} mismatch at "
        f"coefficient {int(coefficient)}, "
        f"ciphertext {int(ciphertext)}, "
        f"component c{int(component)}: "
        f"result={int(actual[coefficient, ciphertext, component])}, "
        f"expected={int(expected[coefficient, component])}"
    )


def write_first_ciphertext_results(
    receive_buffer,
    result_root: Path,
    tower0: int,
    tower1: int,
    ciphertext_count: int,
) -> None:
    actual = np.asarray(
        receive_buffer,
        dtype=np.uint64,
    ).reshape(
        N,
        ciphertext_count,
        OUTPUT_WORDS_PER_CIPHERTEXT,
    )

    first = actual[:, 0, :]

    for component in range(
        OUTPUT_WORDS_PER_CIPHERTEXT
    ):
        lane0, lane1 = split_words(
            first[:, component]
        )

        component_root = (
            result_root
            / f"c{component}"
        )

        component_root.mkdir(
            parents=True,
            exist_ok=True,
        )

        lane0.astype("<u4").tofile(
            component_root
            / f"{tower_name(tower0)}.bin"
        )

        lane1.astype("<u4").tofile(
            component_root
            / f"{tower_name(tower1)}.bin"
        )


def run_complete_batch(
    dma,
    profile_buffer,
    send_buffer,
    receive_buffer,
    pair_data: list[dict[str, object]],
    profile_frames: list[np.ndarray],
    ciphertext_count: int,
    digit_count: int,
    result_root: Path | None,
) -> tuple[float, float]:
    profile_total_us = 0.0
    data_total_us = 0.0

    for pair_index, (
        data,
        profile_frame,
    ) in enumerate(
        zip(
            pair_data,
            profile_frames,
        )
    ):
        profile_buffer[:] = profile_frame

        profile_total_us += send_only(
            dma,
            profile_buffer,
        )

        # Host packing is deliberately outside the timed DMA interval.
        fill_coefficient_major_frame(
            send_buffer,
            data,
            ciphertext_count,
            digit_count,
        )

        data_total_us += run_frame(
            dma,
            send_buffer,
            receive_buffer,
        )

        validate_pair(
            receive_buffer,
            data["expected"],
            ciphertext_count,
            pair_index,
        )

        if result_root is not None:
            write_first_ciphertext_results(
                receive_buffer,
                result_root,
                2 * pair_index,
                2 * pair_index + 1,
                ciphertext_count,
            )

    return (
        profile_total_us,
        data_total_us,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run exact coefficient-major EvalMult plus "
            "host-decomposed OpenFHE BV relinearization on PYNQ-Z2."
        )
    )

    parser.add_argument(
        "--overlay",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--vectors",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--results",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--timed-runs",
        type=int,
        default=5,
    )

    parser.add_argument(
        "--ciphertexts",
        type=int,
        default=8,
    )

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error(
            "--timed-runs must be positive"
        )

    if not 8 <= args.ciphertexts <= MAX_BATCH:
        parser.error(
            f"--ciphertexts must be between 8 and {MAX_BATCH}"
        )

    vector_root = args.vectors.resolve()
    result_root = args.results.resolve()

    metadata = read_json(
        vector_root / "metadata.json"
    )

    if metadata.get("technique") != "BV":
        raise ValueError(
            "board checkpoint requires BV vectors"
        )

    ring_dimension = int(
        metadata["ring_dimension"]
    )

    tower_count = int(
        metadata["q_towers"]
    )

    p_towers = int(
        metadata["p_towers"]
    )

    digit_count = int(
        metadata["digits"]
    )

    digit_towers = int(
        metadata["digit_towers"]
    )

    eval_key_parts = int(
        metadata["eval_key_parts"]
    )

    eval_key_towers = int(
        metadata["eval_key_towers"]
    )

    max_q_bits = int(
        metadata["max_q_modulus_bits"]
    )

    if ring_dimension != N:
        raise ValueError(
            f"overlay requires N={N}"
        )

    if tower_count != 12:
        raise ValueError(
            f"board checkpoint expects 12 Q towers; "
            f"got {tower_count}"
        )

    if tower_count % 2:
        raise ValueError(
            "Q tower count must be even"
        )

    if p_towers != 0:
        raise ValueError(
            "BV vectors unexpectedly contain P towers"
        )

    if not (
        digit_count == DIGIT_COUNT_EXPECTED
        and digit_count == eval_key_parts
        and digit_towers == tower_count
        and eval_key_towers == tower_count
    ):
        raise ValueError(
            "BV digit/evaluation-key dimensions are inconsistent"
        )

    if max_q_bits > 30:
        raise ValueError(
            "current FPGA Barrett datapath supports "
            "at most 30-bit Q moduli"
        )

    pair_count = tower_count // 2

    if pair_count != PAIR_COUNT_EXPECTED:
        raise ValueError(
            f"expected {PAIR_COUNT_EXPECTED} tower pairs"
        )

    words_per_coefficient = (
        EVAL_WORDS_PER_CIPHERTEXT
        * args.ciphertexts
        + digit_count
        * (
            KEY_WORDS_PER_DIGIT
            + DIGIT_WORDS_PER_CIPHERTEXT
            * args.ciphertexts
        )
    )

    legacy_words_per_coefficient = (
        args.ciphertexts
        * (
            EVAL_WORDS_PER_CIPHERTEXT
            + 3 * digit_count
        )
    )

    send_words = (
        2
        + N
        * words_per_coefficient
    )

    receive_words = (
        N
        * args.ciphertexts
        * OUTPUT_WORDS_PER_CIPHERTEXT
    )

    send_bytes = (
        send_words
        * np.dtype(np.uint64).itemsize
    )

    receive_bytes = (
        receive_words
        * np.dtype(np.uint64).itemsize
    )

    if send_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"RLCM input frame is {send_bytes} bytes, "
            f"exceeding the {DMA_LENGTH_WIDTH}-bit DMA limit"
        )

    if receive_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"RLCM output frame is {receive_bytes} bytes, "
            f"exceeding the {DMA_LENGTH_WIDTH}-bit DMA limit"
        )

    result_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    print(
        "Preparing exact paired-tower source vectors..."
    )

    profile_frames: list[np.ndarray] = []
    pair_data: list[dict[str, object]] = []

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1 = tower0 + 1

        profile_frames.append(
            build_profile_frame(
                vector_root,
                tower0,
                tower1,
            )
        )

        pair_data.append(
            load_pair_data(
                vector_root,
                tower0,
                tower1,
                digit_count,
            )
        )

        print(
            f"  pair={pair_index} towers={tower0},{tower1}"
        )

    overlay_path = args.overlay.resolve()

    if overlay_path.with_suffix(".xsa").exists():
        raise RuntimeError(
            "Rename the same-stem XSA before loading the PYNQ overlay"
        )

    overlay = Overlay(
        str(overlay_path),
        download=True,
    )

    dma = resolve_dma(overlay)

    profile_buffer = allocate(
        shape=(3,),
        dtype=np.uint64,
    )

    try:
        require_aligned_buffer(
            profile_buffer,
            "RLPF profile buffer",
        )

        send_buffer = allocate(
            shape=(send_words,),
            dtype=np.uint64,
        )

        try:
            require_aligned_buffer(
                send_buffer,
                "RLCM send buffer",
            )

            receive_buffer = allocate(
                shape=(receive_words,),
                dtype=np.uint64,
            )

            try:
                require_aligned_buffer(
                    receive_buffer,
                    "RLCM receive buffer",
                )

                (
                    warmup_profile_us,
                    warmup_data_us,
                ) = run_complete_batch(
                    dma,
                    profile_buffer,
                    send_buffer,
                    receive_buffer,
                    pair_data,
                    profile_frames,
                    args.ciphertexts,
                    digit_count,
                    result_root,
                )

                profile_timings: list[float] = []
                data_timings: list[float] = []
                total_timings: list[float] = []

                for run_index in range(
                    args.timed_runs
                ):
                    (
                        profile_us,
                        data_us,
                    ) = run_complete_batch(
                        dma,
                        profile_buffer,
                        send_buffer,
                        receive_buffer,
                        pair_data,
                        profile_frames,
                        args.ciphertexts,
                        digit_count,
                        None,
                    )

                    total_us = (
                        profile_us
                        + data_us
                    )

                    profile_timings.append(
                        profile_us
                    )

                    data_timings.append(
                        data_us
                    )

                    total_timings.append(
                        total_us
                    )

                    print(
                        f"run={run_index} exact "
                        f"profile_us={profile_us:.2f} "
                        f"data_us={data_us:.2f} "
                        f"total_us={total_us:.2f}"
                    )

                median_profile_us = statistics.median(
                    profile_timings
                )

                median_data_us = statistics.median(
                    data_timings
                )

                median_total_us = statistics.median(
                    total_timings
                )
            finally:
                receive_buffer.freebuffer()
        finally:
            send_buffer.freebuffer()
    finally:
        profile_buffer.freebuffer()

    input_only_ideal_us = (
        pair_count
        * N
        * words_per_coefficient
        / CLOCK_HZ
        * 1_000_000.0
    )

    estimated_schedule_cycles_per_coefficient = (
        words_per_coefficient
        + ESTIMATED_DRAIN_CYCLES
        + OUTPUT_WORDS_PER_CIPHERTEXT
        * args.ciphertexts
    )

    estimated_schedule_ideal_us = (
        pair_count
        * N
        * estimated_schedule_cycles_per_coefficient
        / CLOCK_HZ
        * 1_000_000.0
    )

    data_us_per_ciphertext = (
        median_data_us
        / args.ciphertexts
    )

    total_us_per_ciphertext = (
        median_total_us
        / args.ciphertexts
    )

    data_rate = (
        1_000_000.0
        / data_us_per_ciphertext
    )

    total_rate = (
        1_000_000.0
        / total_us_per_ciphertext
    )

    verified_tower_components = (
        tower_count
        * args.ciphertexts
        * OUTPUT_WORDS_PER_CIPHERTEXT
    )

    input_reduction = (
        1.0
        - words_per_coefficient
        / legacy_words_per_coefficient
    )

    print()
    print(
        "PASS: every coefficient-major RLCM result "
        "matches OpenFHE"
    )

    print(f"towers={tower_count}")
    print(f"pairs={pair_count}")
    print(f"digits={digit_count}")
    print(f"ciphertexts={args.ciphertexts}")
    print(
        f"words_per_coefficient={words_per_coefficient}"
    )
    print(
        "legacy_words_per_coefficient="
        f"{legacy_words_per_coefficient}"
    )
    print(
        f"input_reduction={input_reduction:.4%}"
    )
    print(f"send_bytes_per_pair={send_bytes}")
    print(f"receive_bytes_per_pair={receive_bytes}")
    print(
        f"total_input_bytes_per_run="
        f"{pair_count * send_bytes}"
    )
    print(
        f"total_output_bytes_per_run="
        f"{pair_count * receive_bytes}"
    )
    print(
        f"warmup_profile_us={warmup_profile_us:.2f}"
    )
    print(
        f"warmup_data_us={warmup_data_us:.2f}"
    )
    print(
        f"median_profile_us={median_profile_us:.2f}"
    )
    print(
        f"median_data_us={median_data_us:.2f}"
    )
    print(
        f"median_total_us={median_total_us:.2f}"
    )
    print(
        f"input_only_ideal_us={input_only_ideal_us:.2f}"
    )
    print(
        "estimated_serialized_schedule_ideal_us="
        f"{estimated_schedule_ideal_us:.2f}"
    )
    print(
        "estimated_schedule_efficiency="
        f"{estimated_schedule_ideal_us / median_data_us:.4%}"
    )
    print(
        f"verified_tower_components="
        f"{verified_tower_components}"
    )
    print(
        "data_us_per_relinearized_EvalMult="
        f"{data_us_per_ciphertext:.2f}"
    )
    print(
        "data_relinearized_EvalMult_per_second="
        f"{data_rate:.2f}"
    )
    print(
        "end_to_end_us_per_relinearized_EvalMult="
        f"{total_us_per_ciphertext:.2f}"
    )
    print(
        "end_to_end_relinearized_EvalMult_per_second="
        f"{total_rate:.2f}"
    )
    print(f"results={result_root}")


if __name__ == "__main__":
    main()
