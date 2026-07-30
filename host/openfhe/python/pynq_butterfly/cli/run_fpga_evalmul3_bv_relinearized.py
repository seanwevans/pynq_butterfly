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
BATCH_COMMAND = np.uint32(0x524C4256)    # RLBV

EVALMUL_WORDS_PER_COEFFICIENT = 4
BV_WORDS_PER_DIGIT = 3
OUTPUT_WORDS_PER_COEFFICIENT = 2

CLOCK_HZ = 100_000_000
MAX_DMA_BYTES = (1 << 26) - 1


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
        bad = int(np.flatnonzero(values > np.uint64(0xFFFFFFFF))[0])

        raise ValueError(
            f"{root}: tower {tower_index}, coefficient {bad} "
            f"does not fit in 32 bits"
        )

    return values.astype(np.uint32)


def pair_words(
    lane0: np.ndarray,
    lane1: np.ndarray,
) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError("paired tower arrays have different shapes")

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
    values = np.asarray(paired, dtype=np.uint64)

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


def write_u32le(
    path: Path,
    words: np.ndarray,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    np.asarray(
        words,
        dtype="<u4",
    ).tofile(path)


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


def build_single_ciphertext_payload(
    vector_root: Path,
    tower0: int,
    tower1: int,
    digit_count: int,
) -> np.ndarray:
    words_per_coefficient = (
        EVALMUL_WORDS_PER_COEFFICIENT
        + BV_WORDS_PER_DIGIT
        * digit_count
    )

    payload = np.empty(
        (
            N,
            words_per_coefficient,
        ),
        dtype=np.uint64,
    )

    input_roots = [
        vector_root / "input_a0_q_eval",
        vector_root / "input_a1_q_eval",
        vector_root / "input_b0_q_eval",
        vector_root / "input_b1_q_eval",
    ]

    for column, root in enumerate(input_roots):
        payload[:, column] = pair_words(
            read_tower_u32(
                root,
                tower0,
            ),
            read_tower_u32(
                root,
                tower1,
            ),
        )

    for digit_index in range(digit_count):
        digit_root = (
            vector_root
            / "digits"
            / digit_name(digit_index)
        )

        key_b_root = (
            vector_root
            / "eval_key_b"
            / digit_name(digit_index)
        )

        key_a_root = (
            vector_root
            / "eval_key_a"
            / digit_name(digit_index)
        )

        base_column = (
            EVALMUL_WORDS_PER_COEFFICIENT
            + BV_WORDS_PER_DIGIT
            * digit_index
        )

        payload[
            :,
            base_column,
        ] = pair_words(
            read_tower_u32(
                digit_root,
                tower0,
            ),
            read_tower_u32(
                digit_root,
                tower1,
            ),
        )

        payload[
            :,
            base_column + 1,
        ] = pair_words(
            read_tower_u32(
                key_b_root,
                tower0,
            ),
            read_tower_u32(
                key_b_root,
                tower1,
            ),
        )

        payload[
            :,
            base_column + 2,
        ] = pair_words(
            read_tower_u32(
                key_a_root,
                tower0,
            ),
            read_tower_u32(
                key_a_root,
                tower1,
            ),
        )

    return payload.reshape(-1)


def build_single_ciphertext_expected(
    vector_root: Path,
    tower0: int,
    tower1: int,
) -> np.ndarray:
    expected = np.empty(
        (
            N,
            OUTPUT_WORDS_PER_COEFFICIENT,
        ),
        dtype=np.uint64,
    )

    expected[:, 0] = pair_words(
        read_tower_u32(
            vector_root
            / "relinearized_c0_q",
            tower0,
        ),
        read_tower_u32(
            vector_root
            / "relinearized_c0_q",
            tower1,
        ),
    )

    expected[:, 1] = pair_words(
        read_tower_u32(
            vector_root
            / "relinearized_c1_q",
            tower0,
        ),
        read_tower_u32(
            vector_root
            / "relinearized_c1_q",
            tower1,
        ),
    )

    return expected.reshape(-1)


def fill_batch_frame(
    send_buffer,
    single_payload: np.ndarray,
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

    offset = 2
    payload_words = int(
        single_payload.size
    )

    for _ in range(ciphertext_count):
        send_buffer[
            offset:offset + payload_words
        ] = single_payload

        offset += payload_words

    if offset != int(send_buffer.size):
        raise RuntimeError(
            f"batch frame filled {offset} words; "
            f"expected {send_buffer.size}"
        )


def validate_pair(
    receive_buffer,
    expected_single: np.ndarray,
    ciphertext_count: int,
    pair_index: int,
) -> None:
    actual = np.asarray(
        receive_buffer,
        dtype=np.uint64,
    ).reshape(
        ciphertext_count,
        expected_single.size,
    )

    mismatches = (
        actual
        != expected_single[
            np.newaxis,
            :,
        ]
    )

    if not np.any(mismatches):
        return

    ciphertext, word = np.argwhere(
        mismatches
    )[0]

    coefficient = int(
        word
        // OUTPUT_WORDS_PER_COEFFICIENT
    )

    component = int(
        word
        % OUTPUT_WORDS_PER_COEFFICIENT
    )

    raise AssertionError(
        f"pair {pair_index} mismatch at "
        f"ciphertext {int(ciphertext)}, "
        f"coefficient {coefficient}, "
        f"component c{component}: "
        f"result={int(actual[ciphertext, word])}, "
        f"expected={int(expected_single[word])}"
    )


def write_pair_results(
    receive_buffer,
    result_root: Path,
    tower0: int,
    tower1: int,
) -> None:
    lane0, lane1 = split_words(
        receive_buffer
    )

    write_u32le(
        result_root
        / f"{tower_name(tower0)}.bin",
        lane0,
    )

    write_u32le(
        result_root
        / f"{tower_name(tower1)}.bin",
        lane1,
    )


def run_complete_ciphertexts(
    dma,
    profile_buffer,
    send_buffer,
    receive_buffer,
    pair_payloads: list[np.ndarray],
    pair_expected: list[np.ndarray],
    profile_frames: list[np.ndarray],
    ciphertext_count: int,
    digit_count: int,
    result_root: Path | None,
) -> tuple[float, float]:
    profile_total_us = 0.0
    data_total_us = 0.0

    for pair_index, (
        profile_frame,
        single_payload,
        expected_single,
    ) in enumerate(
        zip(
            profile_frames,
            pair_payloads,
            pair_expected,
        )
    ):
        profile_buffer[:] = profile_frame

        profile_total_us += send_only(
            dma,
            profile_buffer,
        )

        fill_batch_frame(
            send_buffer,
            single_payload,
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
            expected_single,
            ciphertext_count,
            pair_index,
        )

        if result_root is not None:
            write_pair_results(
                receive_buffer,
                result_root,
                2 * pair_index,
                2 * pair_index + 1,
            )

    return (
        profile_total_us,
        data_total_us,
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run exact fused EvalMultNoRelin plus host-decomposed "
            "OpenFHE BV relinearization on the PYNQ-Z2."
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

    if args.ciphertexts < 1:
        parser.error(
            "--ciphertexts must be positive"
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
        digit_count == eval_key_parts
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

    words_per_coefficient = (
        EVALMUL_WORDS_PER_COEFFICIENT
        + BV_WORDS_PER_DIGIT
        * digit_count
    )

    single_payload_words = (
        N
        * words_per_coefficient
    )

    single_output_words = (
        N
        * OUTPUT_WORDS_PER_COEFFICIENT
    )

    send_words = (
        2
        + args.ciphertexts
        * single_payload_words
    )

    receive_words = (
        args.ciphertexts
        * single_output_words
    )

    send_bytes = (
        send_words
        * np.dtype(np.uint64).itemsize
    )

    receive_bytes = (
        receive_words
        * np.dtype(np.uint64).itemsize
    )

    maximum_ciphertexts = (
        (
            MAX_DMA_BYTES // 8
            - 2
        )
        // single_payload_words
    )

    if send_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"RLBV input frame is {send_bytes} bytes, "
            f"exceeding the 26-bit DMA limit of "
            f"{MAX_DMA_BYTES} bytes. Use at most "
            f"{maximum_ciphertexts} ciphertexts."
        )

    if receive_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"RLBV output frame is {receive_bytes} bytes, "
            f"exceeding the 26-bit DMA limit"
        )

    result_root.mkdir(
        parents=True,
        exist_ok=True,
    )

    print(
        "Preparing paired-tower vectors in normal host memory..."
    )

    profile_frames: list[np.ndarray] = []
    pair_payloads: list[np.ndarray] = []
    pair_expected: list[np.ndarray] = []

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

        pair_payloads.append(
            build_single_ciphertext_payload(
                vector_root,
                tower0,
                tower1,
                digit_count,
            )
        )

        pair_expected.append(
            build_single_ciphertext_expected(
                vector_root,
                tower0,
                tower1,
            )
        )

        print(
            f"  pair={pair_index} towers={tower0},{tower1} "
            f"payload_words={single_payload_words}"
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
                "RLBV send buffer",
            )

            receive_buffer = allocate(
                shape=(receive_words,),
                dtype=np.uint64,
            )

            try:
                require_aligned_buffer(
                    receive_buffer,
                    "RLBV receive buffer",
                )

                (
                    warmup_profile_us,
                    warmup_data_us,
                ) = run_complete_ciphertexts(
                    dma,
                    profile_buffer,
                    send_buffer,
                    receive_buffer,
                    pair_payloads,
                    pair_expected,
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
                    ) = run_complete_ciphertexts(
                        dma,
                        profile_buffer,
                        send_buffer,
                        receive_buffer,
                        pair_payloads,
                        pair_expected,
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

    ideal_data_us = (
        pair_count
        * args.ciphertexts
        * single_payload_words
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
        * OUTPUT_WORDS_PER_COEFFICIENT
    )

    print()
    print(
        "PASS: every fused RLBV relinearized component "
        "matches OpenFHE"
    )

    print(f"towers={tower_count}")
    print(f"pairs={pair_count}")
    print(f"digits={digit_count}")
    print(f"ciphertexts={args.ciphertexts}")
    print(
        f"words_per_coefficient={words_per_coefficient}"
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
        f"maximum_ciphertexts_per_pair_frame="
        f"{maximum_ciphertexts}"
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
        f"stream_efficiency="
        f"{ideal_data_us / median_data_us:.4%}"
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
