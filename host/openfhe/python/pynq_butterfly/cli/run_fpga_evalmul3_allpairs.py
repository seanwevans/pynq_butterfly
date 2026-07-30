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

PROFILE_TABLE_COMMAND = np.uint32(0x45565054)  # EVPT
ALL_PAIRS_COMMAND = np.uint32(0x45563132)      # EV12

INPUT_WORDS_PER_COEFFICIENT = 4
OUTPUT_WORDS_PER_COEFFICIENT = 3

CLOCK_HZ = 100_000_000
MAX_DMA_BYTES = (1 << 26) - 1


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def read_u32le_prefix(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(
        path,
        dtype="<u4",
        count=expected_words,
    )

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found only {values.size} prefix words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def write_u32le(path: Path, words: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    np.asarray(words, dtype="<u4").tofile(path)


def pair_words(lane0: np.ndarray, lane1: np.ndarray) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError("Lane arrays have different shapes")

    return (
        lane0.astype(np.uint64)
        | (lane1.astype(np.uint64) << np.uint64(32))
    )


def split_words(paired: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(paired, dtype=np.uint64)

    return (
        (values & np.uint64(0xFFFFFFFF)).astype(np.uint32),
        np.right_shift(values, np.uint64(32)).astype(np.uint32),
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


def load_profile(path: Path) -> tuple[int, int]:
    metadata = read_json(path / "profile.json")
    modulus = int(metadata["modulus"])
    mu = int(metadata["mu"])

    if not ((1 << 29) < modulus < (1 << 30)):
        raise ValueError(
            f"{path}: modulus {modulus} is outside 2^29 < q < 2^30"
        )

    if mu != (1 << 60) // modulus:
        raise ValueError(
            f"{path}: mu={mu}, expected {(1 << 60) // modulus}"
        )

    if mu >= 1 << 31:
        raise ValueError(f"{path}: mu does not fit 31 bits")

    return modulus, mu


def build_profile_table_frame(
    vector_root: Path,
    tower_count: int,
) -> np.ndarray:
    pair_count = (tower_count + 1) // 2
    frame = np.empty(2 + 2 * pair_count, dtype=np.uint64)

    command_word = (
        np.uint64(PROFILE_TABLE_COMMAND)
        | (np.uint64(PROFILE_TABLE_COMMAND) << np.uint64(32))
    )

    count_word = (
        np.uint64(pair_count)
        | (np.uint64(pair_count) << np.uint64(32))
    )

    frame[0] = command_word
    frame[1] = count_word

    offset = 2

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1 = tower0 + 1 if tower0 + 1 < tower_count else tower0

        modulus0, mu0 = load_profile(
            vector_root / tower_name(tower0)
        )

        modulus1, mu1 = load_profile(
            vector_root / tower_name(tower1)
        )

        frame[offset] = (
            np.uint64(modulus0)
            | (np.uint64(modulus1) << np.uint64(32))
        )

        frame[offset + 1] = (
            np.uint64(mu0)
            | (np.uint64(mu1) << np.uint64(32))
        )

        offset += 2

    return frame


def resolve_dma(overlay: Overlay):
    matches: list[str] = []

    for name, metadata in overlay.ip_dict.items():
        ip_type = str(metadata.get("type", "")).lower()

        if name.lower() == "dma" or "axi_dma" in ip_type:
            matches.append(name)

    if len(matches) != 1:
        inventory = [
            (name, metadata.get("type", ""))
            for name, metadata in overlay.ip_dict.items()
        ]

        raise RuntimeError(
            "Expected exactly one AXI DMA; "
            f"matches={matches}, inventory={inventory}"
        )

    return getattr(overlay, matches[0])


def send_only(dma, buffer) -> float:
    buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()

    return (time.perf_counter_ns() - start_ns) / 1_000.0


def run_frame(dma, send_buffer, receive_buffer) -> float:
    receive_buffer[:] = 0
    send_buffer.flush()
    receive_buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.recvchannel.transfer(receive_buffer)
    dma.sendchannel.transfer(send_buffer)

    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_us = (time.perf_counter_ns() - start_ns) / 1_000.0

    receive_buffer.invalidate()

    return elapsed_us


def require_equal(
    actual: np.ndarray,
    expected: np.ndarray,
    label: str,
) -> None:
    if np.array_equal(actual, expected):
        return

    mismatch = int(np.flatnonzero(actual != expected)[0])
    coefficient_triple = mismatch // 3
    component = mismatch % 3
    ciphertext = coefficient_triple // N
    coefficient = coefficient_triple % N

    raise AssertionError(
        f"{label} mismatch at ciphertext {ciphertext}, "
        f"coefficient {coefficient}, component c{component}: "
        f"result={int(actual[mismatch])}, "
        f"expected={int(expected[mismatch])}"
    )


def validate_all_pairs(
    receive_buffer,
    vector_root: Path,
    result_root: Path,
    tower_count: int,
    ciphertext_count: int,
) -> int:
    pair_count = (tower_count + 1) // 2

    pair_output_words = (
        ciphertext_count
        * N
        * OUTPUT_WORDS_PER_COEFFICIENT
    )

    verified_tower_components = 0

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1_real = tower0 + 1 < tower_count
        tower1 = tower0 + 1 if tower1_real else tower0

        start = pair_index * pair_output_words
        stop = start + pair_output_words

        actual0, actual1 = split_words(
            receive_buffer[start:stop]
        )

        expected0 = read_u32le_prefix(
            vector_root
            / tower_name(tower0)
            / "openfhe_expected.bin",
            pair_output_words,
        )

        expected1 = read_u32le_prefix(
            vector_root
            / tower_name(tower1)
            / "openfhe_expected.bin",
            pair_output_words,
        )

        require_equal(
            actual0,
            expected0,
            f"pair {pair_index} lane0",
        )

        require_equal(
            actual1,
            expected1,
            f"pair {pair_index} lane1",
        )

        write_u32le(
            result_root / f"{tower_name(tower0)}.bin",
            actual0,
        )

        verified_tower_components += ciphertext_count * 3

        if tower1_real:
            write_u32le(
                result_root / f"{tower_name(tower1)}.bin",
                actual1,
            )

            verified_tower_components += ciphertext_count * 3

    return verified_tower_components


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run exact OpenFHE EvalMultNoRelin for every RNS tower pair "
            "inside one EV12 DMA transaction."
        )
    )

    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--timed-runs", type=int, default=5)
    parser.add_argument(
        "--ciphertexts",
        type=int,
        default=64,
    )

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error("--timed-runs must be positive")

    if args.ciphertexts < 1:
        parser.error("--ciphertexts must be positive")

    vector_root = args.vectors.resolve()
    result_root = args.results.resolve()
    metadata = read_json(vector_root / "metadata.json")

    tower_count = int(metadata["tower_count"])
    available_ciphertext_count = int(metadata["ciphertext_count"])
    ring_dimension = int(metadata["ring_dimension"])

    if ring_dimension != N:
        raise ValueError(f"Overlay requires N={N}")

    if args.ciphertexts > available_ciphertext_count:
        parser.error(
            "--ciphertexts exceeds the vector-set ciphertext count "
            f"({available_ciphertext_count})"
        )

    ciphertext_count = args.ciphertexts
    pair_count = (tower_count + 1) // 2

    pair_input_words = (
        ciphertext_count
        * N
        * INPUT_WORDS_PER_COEFFICIENT
    )

    pair_output_words = (
        ciphertext_count
        * N
        * OUTPUT_WORDS_PER_COEFFICIENT
    )

    send_words = 2 + pair_count * pair_input_words
    receive_words = pair_count * pair_output_words

    send_bytes = send_words * np.dtype(np.uint64).itemsize
    receive_bytes = receive_words * np.dtype(np.uint64).itemsize

    if send_bytes > MAX_DMA_BYTES:
        maximum_ciphertexts = (
            (MAX_DMA_BYTES // 8 - 2)
            // (
                pair_count
                * N
                * INPUT_WORDS_PER_COEFFICIENT
            )
        )

        raise ValueError(
            f"EV12 input frame is {send_bytes} bytes, exceeding the "
            f"26-bit simple-DMA limit of {MAX_DMA_BYTES} bytes. "
            f"For {pair_count} pairs and N={N}, use at most "
            f"{maximum_ciphertexts} ciphertexts."
        )

    if receive_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"EV12 output frame is {receive_bytes} bytes, exceeding "
            f"the 26-bit simple-DMA limit of {MAX_DMA_BYTES} bytes"
        )

    result_root.mkdir(parents=True, exist_ok=True)

    overlay_path = args.overlay.resolve()

    if overlay_path.with_suffix(".xsa").exists():
        raise RuntimeError(
            "Rename the same-stem XSA before loading the PYNQ overlay"
        )

    overlay = Overlay(str(overlay_path), download=True)
    dma = resolve_dma(overlay)

    profile_frame = build_profile_table_frame(
        vector_root,
        tower_count,
    )

    profile_buffer = allocate(
        shape=profile_frame.shape,
        dtype=np.uint64,
    )

    try:
        require_aligned_buffer(
            profile_buffer,
            "profile-table buffer",
        )

        profile_buffer[:] = profile_frame
        profile_us = send_only(dma, profile_buffer)
        time.sleep(0.001)
    finally:
        profile_buffer.freebuffer()

    send_buffer = allocate(
        shape=(send_words,),
        dtype=np.uint64,
    )

    try:
        require_aligned_buffer(
            send_buffer,
            "EV12 send buffer",
        )

        command_word = (
            np.uint64(ALL_PAIRS_COMMAND)
            | (np.uint64(ALL_PAIRS_COMMAND) << np.uint64(32))
        )

        header_word = (
            np.uint64(ciphertext_count)
            | (np.uint64(pair_count) << np.uint64(32))
        )

        send_buffer[0] = command_word
        send_buffer[1] = header_word

        offset = 2

        for pair_index in range(pair_count):
            tower0 = 2 * pair_index
            tower1 = tower0 + 1 if tower0 + 1 < tower_count else tower0

            dma0 = read_u32le_prefix(
                vector_root
                / tower_name(tower0)
                / "dma_input.bin",
                pair_input_words,
            )

            dma1 = read_u32le_prefix(
                vector_root
                / tower_name(tower1)
                / "dma_input.bin",
                pair_input_words,
            )

            paired = pair_words(dma0, dma1)
            send_buffer[offset:offset + pair_input_words] = paired
            offset += pair_input_words

            del dma0
            del dma1
            del paired

        if offset != send_words:
            raise RuntimeError(
                f"EV12 send-frame fill stopped at {offset}, "
                f"expected {send_words}"
            )

        receive_buffer = allocate(
            shape=(receive_words,),
            dtype=np.uint64,
        )

        try:
            require_aligned_buffer(
                receive_buffer,
                "EV12 receive buffer",
            )

            warmup_us = run_frame(
                dma,
                send_buffer,
                receive_buffer,
            )

            verified_tower_components = validate_all_pairs(
                receive_buffer,
                vector_root,
                result_root,
                tower_count,
                ciphertext_count,
            )

            timings: list[float] = []

            for run_index in range(args.timed_runs):
                elapsed_us = run_frame(
                    dma,
                    send_buffer,
                    receive_buffer,
                )

                validate_all_pairs(
                    receive_buffer,
                    vector_root,
                    result_root,
                    tower_count,
                    ciphertext_count,
                )

                timings.append(elapsed_us)

                print(
                    f"run={run_index} exact elapsed_us={elapsed_us:.2f}"
                )

            median_us = statistics.median(timings)
        finally:
            receive_buffer.freebuffer()
    finally:
        send_buffer.freebuffer()

    ideal_us = (
        pair_count
        * ciphertext_count
        * INPUT_WORDS_PER_COEFFICIENT
        * N
        / CLOCK_HZ
        * 1_000_000.0
    )

    compute_us_per_ciphertext = (
        median_us / ciphertext_count
    )

    end_to_end_us_per_ciphertext = (
        median_us + profile_us
    ) / ciphertext_count

    compute_rate = (
        1_000_000.0 / compute_us_per_ciphertext
    )

    end_to_end_rate = (
        1_000_000.0 / end_to_end_us_per_ciphertext
    )

    print()
    print(
        "PASS: every EV12 fused evaluation-domain component "
        "matches OpenFHE"
    )
    print(f"towers={tower_count}")
    print(f"pairs={pair_count}")
    print(f"ciphertexts={ciphertext_count}")
    print(f"send_bytes={send_bytes}")
    print(f"receive_bytes={receive_bytes}")
    print(f"profile_table_us={profile_us:.2f}")
    print(f"warmup_us={warmup_us:.2f}")
    print(f"median_us={median_us:.2f}")
    print(f"stream_efficiency={ideal_us / median_us:.4%}")
    print(
        f"verified_tower_components={verified_tower_components}"
    )
    print(
        "compute_us_per_EvalMultNoRelin="
        f"{compute_us_per_ciphertext:.2f}"
    )
    print(
        "compute_EvalMultNoRelin_per_second="
        f"{compute_rate:.2f}"
    )
    print(
        "end_to_end_us_per_EvalMultNoRelin="
        f"{end_to_end_us_per_ciphertext:.2f}"
    )
    print(
        "end_to_end_EvalMultNoRelin_per_second="
        f"{end_to_end_rate:.2f}"
    )
    print(f"results={result_root}")


if __name__ == "__main__":
    main()
