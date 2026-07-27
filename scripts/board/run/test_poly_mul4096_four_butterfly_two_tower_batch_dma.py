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
TWIDDLES = 4095

PROFILE_COMMAND = np.uint32(0x50524F46)
PRODUCT_COMMAND = np.uint32(0x4D554C31)
BATCH_COMMAND = np.uint32(0x4D554C42)

PROFILE_WORDS = 16_385
PROFILE_BYTES = PROFILE_WORDS * 8

CORE_CYCLES = 22_968
INPUT_WORDS_PER_PRODUCT = 2 * N
OUTPUT_STATE_CYCLES_PER_PRODUCT = 2 * N
DIRECT_CYCLES_PER_PRODUCT = (
    INPUT_WORDS_PER_PRODUCT
    + CORE_CYCLES
    + OUTPUT_STATE_CYCLES_PER_PRODUCT
)


def read_mem(path: Path, expected_words: int) -> np.ndarray:
    values = [
        int(line.strip(), 16)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

    if len(values) != expected_words:
        raise ValueError(
            f"{path}: found {len(values)} words; expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def read_u32le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def pair_words(lane0: np.ndarray, lane1: np.ndarray) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError("Lane arrays have different shapes")

    return (
        lane0.astype(np.uint64)
        | (lane1.astype(np.uint64) << np.uint64(32))
    )


def build_profile_lane(
    profile_directory: Path,
) -> tuple[np.uint32, np.uint32, np.ndarray]:
    metadata = json.loads(
        (profile_directory / "profile.json").read_text(encoding="utf-8")
    )

    modulus = int(metadata["modulus"])
    reciprocal = (1 << 60) // modulus

    if reciprocal >= 1 << 31:
        raise ValueError(
            f"{profile_directory}: reciprocal {reciprocal} does not fit 31 bits"
        )

    payload = np.concatenate(
        [
            read_mem(profile_directory / "twist_factors.mem", N),
            read_mem(profile_directory / "forward_twiddles.mem", TWIDDLES),
            read_mem(profile_directory / "inverse_twiddles.mem", TWIDDLES),
            read_mem(profile_directory / "inverse_scale_factors.mem", N),
        ]
    ).astype(np.uint32, copy=False)

    if payload.size != 16_382:
        raise RuntimeError(
            f"Profile payload contains {payload.size} words"
        )

    return np.uint32(modulus), np.uint32(reciprocal), payload


def build_profile_frame(vector_root: Path) -> np.ndarray:
    modulus0, reciprocal0, payload0 = build_profile_lane(
        vector_root / "profile0"
    )
    modulus1, reciprocal1, payload1 = build_profile_lane(
        vector_root / "profile1"
    )

    lane0 = np.empty(PROFILE_WORDS, dtype=np.uint32)
    lane1 = np.empty(PROFILE_WORDS, dtype=np.uint32)

    lane0[0] = PROFILE_COMMAND
    lane1[0] = PROFILE_COMMAND
    lane0[1] = modulus0
    lane1[1] = modulus1
    lane0[2] = reciprocal0
    lane1[2] = reciprocal1
    lane0[3:] = payload0
    lane1[3:] = payload1

    return pair_words(lane0, lane1)


def load_product_vectors(
    vector_root: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    dma0 = read_u32le(
        vector_root / "tower0" / "dma_input.bin",
        2 * N,
    )
    dma1 = read_u32le(
        vector_root / "tower1" / "dma_input.bin",
        2 * N,
    )
    expected0 = read_u32le(
        vector_root / "tower0" / "openfhe_expected.bin",
        N,
    )
    expected1 = read_u32le(
        vector_root / "tower1" / "openfhe_expected.bin",
        N,
    )

    return dma0, dma1, expected0, expected1


def build_single_frame(dma0: np.ndarray, dma1: np.ndarray) -> np.ndarray:
    lane0 = np.empty(1 + 2 * N, dtype=np.uint32)
    lane1 = np.empty(1 + 2 * N, dtype=np.uint32)
    lane0[0] = PRODUCT_COMMAND
    lane1[0] = PRODUCT_COMMAND
    lane0[1:] = dma0
    lane1[1:] = dma1
    return pair_words(lane0, lane1)


def build_batch_frame(
    dma0: np.ndarray,
    dma1: np.ndarray,
    batch_size: int,
) -> np.ndarray:
    if batch_size < 1:
        raise ValueError("batch_size must be positive")

    words = 2 + batch_size * 2 * N
    lane0 = np.empty(words, dtype=np.uint32)
    lane1 = np.empty(words, dtype=np.uint32)

    lane0[0] = BATCH_COMMAND
    lane1[0] = BATCH_COMMAND
    lane0[1] = np.uint32(batch_size)
    lane1[1] = np.uint32(batch_size)

    lane0[2:] = np.tile(dma0, batch_size)
    lane1[2:] = np.tile(dma1, batch_size)

    return pair_words(lane0, lane1)


def split_results(paired: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(paired, dtype=np.uint64)
    lane0 = (values & np.uint64(0xFFFFFFFF)).astype(np.uint32)
    lane1 = np.right_shift(values, np.uint64(32)).astype(np.uint32)
    return lane0, lane1


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


def validate_batch(
    paired: np.ndarray,
    expected0: np.ndarray,
    expected1: np.ndarray,
    batch_size: int,
    label: str,
) -> None:
    actual0, actual1 = split_results(paired)
    expected0_batch = np.tile(expected0, batch_size)
    expected1_batch = np.tile(expected1, batch_size)

    for actual, expected, tower in (
        (actual0, expected0_batch, 0),
        (actual1, expected1_batch, 1),
    ):
        if np.array_equal(actual, expected):
            continue

        mismatch = int(np.flatnonzero(actual != expected)[0])
        product = mismatch // N
        coefficient = mismatch % N
        raise AssertionError(
            f"{label} tower {tower} mismatch at product {product}, "
            f"coefficient {coefficient}: result={int(actual[mismatch])}, "
            f"expected={int(expected[mismatch])}"
        )


def parse_batch_sizes(text: str) -> list[int]:
    result: list[int] = []

    for token in text.split(","):
        token = token.strip()
        if not token:
            continue
        value = int(token)
        if value < 1:
            raise ValueError("batch sizes must be positive")
        if value not in result:
            result.append(value)

    if not result:
        raise ValueError("at least one batch size is required")

    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Benchmark batched four-butterfly two-tower N=4096 "
            "multiplication on PYNQ-Z2."
        )
    )
    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--batch-sizes", default="1,2,4,8,16")
    parser.add_argument("--timed-runs", type=int, default=5)
    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error("--timed-runs must be positive")

    try:
        batch_sizes = parse_batch_sizes(args.batch_sizes)
    except ValueError as exc:
        parser.error(str(exc))

    vector_root = args.vectors.resolve()
    profile_frame = build_profile_frame(vector_root)
    dma0, dma1, expected0, expected1 = load_product_vectors(vector_root)

    overlay = Overlay(str(args.overlay.resolve()), download=True)
    dma = resolve_dma(overlay)

    profile_buffer = allocate(
        shape=(PROFILE_WORDS,),
        dtype=np.uint64,
    )

    try:
        profile_buffer[:] = profile_frame
        profile_us = send_only(dma, profile_buffer)
        time.sleep(0.001)

        print("PASS: q0 and q1 profiles loaded concurrently")
        print(f"Dual profile frame: {PROFILE_BYTES} bytes")
        print(f"Dual profile load: {profile_us:.2f} us")

        # Preserve and validate the original MUL1 path once.
        single_frame = build_single_frame(dma0, dma1)
        single_send = allocate(shape=single_frame.shape, dtype=np.uint64)
        single_recv = allocate(shape=(N,), dtype=np.uint64)

        try:
            single_send[:] = single_frame
            single_us = run_frame(dma, single_send, single_recv)
            validate_batch(
                single_recv,
                expected0,
                expected1,
                1,
                "MUL1 validation",
            )
            print("PASS: MUL1 remains exact")
            print(f"MUL1 physical time: {single_us:.2f} us")
        finally:
            single_send.freebuffer()
            single_recv.freebuffer()

        print()
        print("Batched measurements")
        print(
            "batch  median_us  us/product  products/s  "
            "ideal_us/product  efficiency"
        )

        for batch_size in batch_sizes:
            frame = build_batch_frame(dma0, dma1, batch_size)
            send_buffer = allocate(shape=frame.shape, dtype=np.uint64)
            receive_buffer = allocate(
                shape=(batch_size * N,),
                dtype=np.uint64,
            )

            try:
                send_buffer[:] = frame

                warmup_us = run_frame(
                    dma,
                    send_buffer,
                    receive_buffer,
                )
                validate_batch(
                    receive_buffer,
                    expected0,
                    expected1,
                    batch_size,
                    f"MULB warmup batch {batch_size}",
                )

                timings_us: list[float] = []

                for run_index in range(args.timed_runs):
                    elapsed_us = run_frame(
                        dma,
                        send_buffer,
                        receive_buffer,
                    )
                    validate_batch(
                        receive_buffer,
                        expected0,
                        expected1,
                        batch_size,
                        f"MULB batch {batch_size} run {run_index}",
                    )
                    timings_us.append(elapsed_us)

                median_us = statistics.median(timings_us)
                us_per_product = median_us / batch_size
                products_per_second = (
                    batch_size * 1_000_000.0 / median_us
                )
                ideal_total_cycles = (
                    2 + batch_size * DIRECT_CYCLES_PER_PRODUCT
                )
                ideal_us_per_product = (
                    ideal_total_cycles / 100.0 / batch_size
                )
                efficiency = ideal_us_per_product / us_per_product

                print(
                    f"{batch_size:5d}  "
                    f"{median_us:9.2f}  "
                    f"{us_per_product:10.2f}  "
                    f"{products_per_second:10.2f}  "
                    f"{ideal_us_per_product:16.2f}  "
                    f"{efficiency:9.1%}"
                )
                print(
                    f"       PASS exact; warmup={warmup_us:.2f} us; "
                    f"min/max={min(timings_us):.2f}/{max(timings_us):.2f} us"
                )
            finally:
                send_buffer.freebuffer()
                receive_buffer.freebuffer()

        print()
        print("PASS: every MUL1/MULB result matches OpenFHE")
    finally:
        profile_buffer.freebuffer()


if __name__ == "__main__":
    main()
