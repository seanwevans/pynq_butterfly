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
BATCH_COMMAND = np.uint32(0x4D554C42)
BATCH_COUNT = np.uint32(2)

PROFILE_WORDS = 16_384
PROFILE_BYTES = 131_072

BATCH_INPUT_WORDS = 16_386
BATCH_INPUT_BYTES = 131_088

BATCH_OUTPUT_WORDS = 8_192
BATCH_OUTPUT_BYTES = 65_536

PER_PRODUCT_CORE_CYCLES = 631_810
BATCH_CORE_CYCLES = 1_263_620
BATCH_DRAIN_CYCLES = 2
BATCH_CORE_PLUS_DRAIN_CYCLES = 1_263_622

BATCH_CORE_PLUS_DRAIN_US = 12_636.22
AMORTIZED_CORE_PLUS_DRAIN_US = 6_318.11

OPENFHE_REFERENCE_US = 7_161.35
PREVIOUS_SINGLE_PRODUCT_MEDIAN_US = 7_186.59


def read_mem(
    path: Path,
    expected_words: int,
) -> np.ndarray:
    values = [
        int(line.strip(), 16)
        for line in path.read_text(
            encoding="utf-8"
        ).splitlines()
        if line.strip()
    ]

    if len(values) != expected_words:
        raise ValueError(
            f"{path}: found {len(values)} words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def read_u32le(
    path: Path,
    expected_words: int,
) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def pair_words(
    lane0: np.ndarray,
    lane1: np.ndarray,
) -> np.ndarray:
    return (
        lane0.astype(np.uint64)
        | (
            lane1.astype(np.uint64)
            << np.uint64(32)
        )
    )


def build_profile_lane(
    profile_directory: Path,
) -> tuple[np.uint32, np.ndarray]:
    metadata = json.loads(
        (
            profile_directory
            / "profile.json"
        ).read_text(
            encoding="utf-8"
        )
    )

    payload = np.concatenate([
        read_mem(
            profile_directory / "twist_factors.mem",
            N,
        ),
        read_mem(
            profile_directory / "forward_twiddles.mem",
            TWIDDLES,
        ),
        read_mem(
            profile_directory / "inverse_twiddles.mem",
            TWIDDLES,
        ),
        read_mem(
            profile_directory / "inverse_scale_factors.mem",
            N,
        ),
    ]).astype(np.uint32, copy=False)

    if payload.size != 16_382:
        raise RuntimeError(
            f"Profile payload contains {payload.size} words"
        )

    return np.uint32(metadata["modulus"]), payload


def build_profile_frame(
    batch_root: Path,
) -> np.ndarray:
    product0 = batch_root / "product0"

    modulus0, payload0 = build_profile_lane(
        product0 / "profile0"
    )

    modulus1, payload1 = build_profile_lane(
        product0 / "profile1"
    )

    product1 = batch_root / "product1"

    check_modulus0, check_payload0 = build_profile_lane(
        product1 / "profile0"
    )

    check_modulus1, check_payload1 = build_profile_lane(
        product1 / "profile1"
    )

    if (
        modulus0 != check_modulus0
        or modulus1 != check_modulus1
        or not np.array_equal(payload0, check_payload0)
        or not np.array_equal(payload1, check_payload1)
    ):
        raise ValueError(
            "Runtime profiles differ between batch products"
        )

    lane0 = np.empty(PROFILE_WORDS, dtype=np.uint32)
    lane1 = np.empty(PROFILE_WORDS, dtype=np.uint32)

    lane0[0] = PROFILE_COMMAND
    lane1[0] = PROFILE_COMMAND

    lane0[1] = modulus0
    lane1[1] = modulus1

    lane0[2:] = payload0
    lane1[2:] = payload1

    return pair_words(lane0, lane1)


def read_product(
    product_root: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    dma0 = read_u32le(
        product_root / "tower0" / "dma_input.bin",
        2 * N,
    )

    dma1 = read_u32le(
        product_root / "tower1" / "dma_input.bin",
        2 * N,
    )

    expected0 = read_u32le(
        product_root / "tower0" / "openfhe_expected.bin",
        N,
    )

    expected1 = read_u32le(
        product_root / "tower1" / "openfhe_expected.bin",
        N,
    )

    return dma0, dma1, expected0, expected1


def build_batch_frame(
    batch_root: Path,
) -> tuple[np.ndarray, list[tuple[np.ndarray, np.ndarray]]]:
    product0 = read_product(
        batch_root / "product0"
    )

    product1 = read_product(
        batch_root / "product1"
    )

    lane0 = np.empty(BATCH_INPUT_WORDS, dtype=np.uint32)
    lane1 = np.empty(BATCH_INPUT_WORDS, dtype=np.uint32)

    lane0[0] = BATCH_COMMAND
    lane1[0] = BATCH_COMMAND

    lane0[1] = BATCH_COUNT
    lane1[1] = BATCH_COUNT

    lane0[2 : 2 + 2 * N] = product0[0]
    lane1[2 : 2 + 2 * N] = product0[1]

    lane0[2 + 2 * N :] = product1[0]
    lane1[2 + 2 * N :] = product1[1]

    expected = [
        (product0[2], product0[3]),
        (product1[2], product1[3]),
    ]

    return pair_words(lane0, lane1), expected


def split_results(
    paired: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(paired, dtype=np.uint64)

    lane0 = (
        values
        & np.uint64(0xFFFFFFFF)
    ).astype(np.uint32)

    lane1 = np.right_shift(
        values,
        np.uint64(32),
    ).astype(np.uint32)

    return lane0, lane1


def validate_product(
    actual0: np.ndarray,
    actual1: np.ndarray,
    expected0: np.ndarray,
    expected1: np.ndarray,
    label: str,
) -> None:
    for lane, actual, expected in (
        (0, actual0, expected0),
        (1, actual1, expected1),
    ):
        if np.array_equal(actual, expected):
            continue

        mismatch = int(
            np.flatnonzero(actual != expected)[0]
        )

        raise AssertionError(
            f"{label} tower {lane} mismatch at coefficient "
            f"{mismatch}: result={int(actual[mismatch])}, "
            f"expected={int(expected[mismatch])}"
        )


def validate_batch(
    paired: np.ndarray,
    expected: list[tuple[np.ndarray, np.ndarray]],
    label: str,
) -> tuple[np.ndarray, np.ndarray]:
    lane0, lane1 = split_results(paired)

    for product_index in range(2):
        start = product_index * N
        stop = start + N

        validate_product(
            lane0[start:stop],
            lane1[start:stop],
            expected[product_index][0],
            expected[product_index][1],
            f"{label} product {product_index}",
        )

    return lane0, lane1


def resolve_dma(overlay: Overlay):
    names = [
        name
        for name in overlay.ip_dict
        if "dma" in name.lower()
    ]

    if len(names) != 1:
        raise RuntimeError(
            "Expected exactly one DMA; "
            f"found {names}"
        )

    return getattr(overlay, names[0])


def send_only(dma, buffer) -> float:
    buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()

    return (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0


def run_batch(
    dma,
    send_buffer,
    receive_buffer,
) -> float:
    receive_buffer[:] = 0

    send_buffer.flush()
    receive_buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.recvchannel.transfer(receive_buffer)
    dma.sendchannel.transfer(send_buffer)

    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_us = (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0

    receive_buffer.invalidate()

    return elapsed_us


def main() -> None:
    parser = argparse.ArgumentParser()

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
        "--output",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--timed-batches",
        type=int,
        default=20,
    )

    parser.add_argument(
        "--openfhe-reference-us",
        type=float,
        default=OPENFHE_REFERENCE_US,
    )

    args = parser.parse_args()

    vector_root = args.vectors.resolve()

    profile_frame = build_profile_frame(
        vector_root
    )

    batch_frame, expected = build_batch_frame(
        vector_root
    )

    overlay = Overlay(
        str(args.overlay.resolve()),
        download=True,
    )

    dma = resolve_dma(overlay)

    profile_buffer = allocate(
        shape=(PROFILE_WORDS,),
        dtype=np.uint64,
    )

    batch_buffer = allocate(
        shape=(BATCH_INPUT_WORDS,),
        dtype=np.uint64,
    )

    receive_buffer = allocate(
        shape=(BATCH_OUTPUT_WORDS,),
        dtype=np.uint64,
    )

    try:
        profile_buffer[:] = profile_frame
        batch_buffer[:] = batch_frame

        profile_us = send_only(
            dma,
            profile_buffer,
        )

        time.sleep(0.001)

        print(
            "PASS: q0 and q1 profiles loaded concurrently"
        )

        print(
            f"Dual profile load: {profile_us:.2f} us"
        )

        first_us = run_batch(
            dma,
            batch_buffer,
            receive_buffer,
        )

        final0, final1 = validate_batch(
            receive_buffer,
            expected,
            "First batch",
        )

        print(
            "PASS: first batch returned two exact OpenFHE products"
        )

        print(
            f"First batch: {first_us:.2f} us"
        )

        print(
            f"First amortized product: {first_us / 2.0:.2f} us"
        )

        timings: list[float] = []

        for index in range(args.timed_batches):
            elapsed_us = run_batch(
                dma,
                batch_buffer,
                receive_buffer,
            )

            final0, final1 = validate_batch(
                receive_buffer,
                expected,
                f"Timed batch {index}",
            )

            timings.append(elapsed_us)

        output_root = args.output.resolve()
        output_root.mkdir(
            parents=True,
            exist_ok=True,
        )

        for product_index in range(2):
            start = product_index * N
            stop = start + N

            np.asarray(
                final0[start:stop],
                dtype="<u4",
            ).tofile(
                output_root
                / f"fpga_product{product_index}_tower0.bin"
            )

            np.asarray(
                final1[start:stop],
                dtype="<u4",
            ).tofile(
                output_root
                / f"fpga_product{product_index}_tower1.bin"
            )

        ordered = sorted(timings)

        p95_index = max(
            0,
            int(np.ceil(0.95 * len(ordered))) - 1,
        )

        batch_median_us = statistics.median(timings)
        batch_mean_us = statistics.fmean(timings)
        batch_p95_us = ordered[p95_index]

        amortized_median_us = batch_median_us / 2.0
        amortized_mean_us = batch_mean_us / 2.0
        amortized_p95_us = batch_p95_us / 2.0

        batch_overhead_us = (
            batch_median_us
            - BATCH_CORE_PLUS_DRAIN_US
        )

        amortized_overhead_us = (
            batch_overhead_us
            / 2.0
        )

        cpu_speedup = (
            args.openfhe_reference_us
            / amortized_median_us
        )

        single_overlay_speedup = (
            PREVIOUS_SINGLE_PRODUCT_MEDIAN_US
            / amortized_median_us
        )

        batch_ceiling = (
            1_000_000.0
            / BATCH_CORE_PLUS_DRAIN_US
        )

        amortized_ceiling = (
            2_000_000.0
            / BATCH_CORE_PLUS_DRAIN_US
        )

        print(
            f"PASS: {args.timed_batches} timed batches "
            "returned four exact tower results each"
        )

        print(
            f"Minimum batch: {min(timings):.2f} us"
        )

        print(
            f"Median batch: {batch_median_us:.2f} us"
        )

        print(
            f"Mean batch: {batch_mean_us:.2f} us"
        )

        print(
            f"p95 batch: {batch_p95_us:.2f} us"
        )

        print(
            f"Maximum batch: {max(timings):.2f} us"
        )

        print(
            f"Median per DCRTPoly product: "
            f"{amortized_median_us:.2f} us"
        )

        print(
            f"Mean per DCRTPoly product: "
            f"{amortized_mean_us:.2f} us"
        )

        print(
            f"p95 per DCRTPoly product: "
            f"{amortized_p95_us:.2f} us"
        )

        print(
            f"Measured DCRTPoly products/s: "
            f"{1_000_000.0 / amortized_median_us:.2f}"
        )

        print(
            f"Measured individual tower products/s: "
            f"{2_000_000.0 / amortized_median_us:.2f}"
        )

        print(
            f"Arithmetic batch ceiling: "
            f"{batch_ceiling:.2f} batches/s"
        )

        print(
            f"Arithmetic product ceiling: "
            f"{amortized_ceiling:.2f} DCRTPoly products/s"
        )

        print(
            f"Per-product core cycles: "
            f"{PER_PRODUCT_CORE_CYCLES}"
        )

        print(
            f"Batch core cycles: "
            f"{BATCH_CORE_CYCLES}"
        )

        print(
            f"Batch drain cycles: "
            f"{BATCH_DRAIN_CYCLES}"
        )

        print(
            f"Batch core plus drain cycles: "
            f"{BATCH_CORE_PLUS_DRAIN_CYCLES}"
        )

        print(
            f"Batch core plus drain latency: "
            f"{BATCH_CORE_PLUS_DRAIN_US:.2f} us"
        )

        print(
            f"Median batch DMA/software overhead: "
            f"{batch_overhead_us:.2f} us"
        )

        print(
            f"Amortized DMA/software overhead per product: "
            f"{amortized_overhead_us:.2f} us"
        )

        print(
            f"Speedup versus single-product FPGA median: "
            f"{single_overlay_speedup:.3f}x"
        )

        if amortized_median_us < args.openfhe_reference_us:
            print(
                "PASS: amortized FPGA median is "
                f"{cpu_speedup:.3f}x faster than the "
                "supplied OpenFHE reference"
            )
        else:
            print(
                "INFO: amortized FPGA median is "
                f"{1.0 / cpu_speedup:.3f}x slower than the "
                "supplied OpenFHE reference"
            )

        print(
            "PASS board batch-of-two OpenFHE stage"
        )

    finally:
        profile_buffer.freebuffer()
        batch_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
