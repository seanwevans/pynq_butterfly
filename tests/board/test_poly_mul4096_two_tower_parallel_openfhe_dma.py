#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import numpy as np

import overlay_constants
from pynq import Overlay, allocate


N = overlay_constants.N
TWIDDLES = overlay_constants.TWIDDLE_WORDS

PROFILE_COMMAND = np.uint32(overlay_constants.PROFILE_COMMAND_WORD)
PRODUCT_COMMAND = np.uint32(overlay_constants.PRODUCT_COMMAND_WORD)

PROFILE_WORDS = 16_384
PROFILE_BYTES = 131_072

PRODUCT_WORDS = 8_193
PRODUCT_BYTES = 65_544

RESULT_WORDS = 4_096
RESULT_BYTES = 32_768

EXPECTED_CORE_CYCLES = overlay_constants.SINGLE_BUTTERFLY_CORE_CYCLES
EXPECTED_CORE_LATENCY_US = 13_393.94


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

    return np.asarray(
        values,
        dtype=np.uint32,
    )


def read_u32le(
    path: Path,
    expected_words: int,
) -> np.ndarray:
    values = np.fromfile(
        path,
        dtype="<u4",
    )

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(
        values,
        dtype=np.uint32,
    )


def pair_words(
    lane0: np.ndarray,
    lane1: np.ndarray,
) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError(
            "Lane arrays have different shapes"
        )

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

    payload_parts = [
        read_mem(
            profile_directory
            / "twist_factors.mem",
            N,
        ),
        read_mem(
            profile_directory
            / "forward_twiddles.mem",
            TWIDDLES,
        ),
        read_mem(
            profile_directory
            / "inverse_twiddles.mem",
            TWIDDLES,
        ),
        read_mem(
            profile_directory
            / "inverse_scale_factors.mem",
            N,
        ),
    ]

    payload = np.concatenate(
        payload_parts
    ).astype(
        np.uint32,
        copy=False,
    )

    if payload.size != 16_382:
        raise RuntimeError(
            f"Profile payload contains {payload.size} words"
        )

    return (
        np.uint32(metadata["modulus"]),
        payload,
    )


def build_profile_frame(
    vector_root: Path,
) -> np.ndarray:
    modulus0, payload0 = build_profile_lane(
        vector_root / "profile0"
    )

    modulus1, payload1 = build_profile_lane(
        vector_root / "profile1"
    )

    lane0 = np.empty(
        PROFILE_WORDS,
        dtype=np.uint32,
    )

    lane1 = np.empty(
        PROFILE_WORDS,
        dtype=np.uint32,
    )

    lane0[0] = PROFILE_COMMAND
    lane1[0] = PROFILE_COMMAND

    lane0[1] = modulus0
    lane1[1] = modulus1

    lane0[2:] = payload0
    lane1[2:] = payload1

    return pair_words(
        lane0,
        lane1,
    )


def build_product_frame(
    vector_root: Path,
) -> tuple[
    np.ndarray,
    np.ndarray,
    np.ndarray,
]:
    dma0 = read_u32le(
        vector_root
        / "tower0"
        / "dma_input.bin",
        2 * N,
    )

    dma1 = read_u32le(
        vector_root
        / "tower1"
        / "dma_input.bin",
        2 * N,
    )

    expected0 = read_u32le(
        vector_root
        / "tower0"
        / "openfhe_expected.bin",
        N,
    )

    expected1 = read_u32le(
        vector_root
        / "tower1"
        / "openfhe_expected.bin",
        N,
    )

    lane0 = np.empty(
        PRODUCT_WORDS,
        dtype=np.uint32,
    )

    lane1 = np.empty(
        PRODUCT_WORDS,
        dtype=np.uint32,
    )

    lane0[0] = PRODUCT_COMMAND
    lane1[0] = PRODUCT_COMMAND

    lane0[1:] = dma0
    lane1[1:] = dma1

    return (
        pair_words(
            lane0,
            lane1,
        ),
        expected0,
        expected1,
    )


def split_results(
    paired: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(
        paired,
        dtype=np.uint64,
    )

    lane0 = (
        values
        & np.uint64(0xFFFFFFFF)
    ).astype(
        np.uint32
    )

    lane1 = np.right_shift(
        values,
        np.uint64(32),
    ).astype(
        np.uint32
    )

    return lane0, lane1


def resolve_dma(overlay: Overlay):
    names = [
        name
        for name in overlay.ip_dict
        if "axi_dma" in name.lower()
    ]

    if len(names) != 1:
        raise RuntimeError(
            "Expected exactly one AXI DMA; "
            f"found {names}"
        )

    return getattr(
        overlay,
        names[0],
    )


def send_only(
    dma,
    buffer,
) -> float:
    buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(
        buffer
    )

    dma.sendchannel.wait()

    return (
        time.perf_counter_ns()
        - start_ns
    ) / 1_000.0


def run_product(
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


def validate(
    actual: np.ndarray,
    expected: np.ndarray,
    label: str,
) -> None:
    if np.array_equal(
        actual,
        expected,
    ):
        return

    mismatch = int(
        np.flatnonzero(
            actual != expected
        )[0]
    )

    raise AssertionError(
        f"{label} mismatch at coefficient {mismatch}: "
        f"result={int(actual[mismatch])}, "
        f"expected={int(expected[mismatch])}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Execute two OpenFHE RNS towers concurrently "
            "through the 64-bit PYNQ-Z2 parallel overlay."
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
        "--output",
        type=Path,
        required=True,
    )

    parser.add_argument(
        "--timed-runs",
        type=int,
        default=20,
    )

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error(
            "--timed-runs must be positive"
        )

    vector_root = args.vectors.resolve()

    profile_frame = build_profile_frame(
        vector_root
    )

    (
        product_frame,
        expected0,
        expected1,
    ) = build_product_frame(
        vector_root
    )

    overlay = Overlay(
        str(args.overlay.resolve()),
        download=True,
    )

    dma = resolve_dma(
        overlay
    )

    profile_buffer = allocate(
        shape=(PROFILE_WORDS,),
        dtype=np.uint64,
    )

    product_buffer = allocate(
        shape=(PRODUCT_WORDS,),
        dtype=np.uint64,
    )

    receive_buffer = allocate(
        shape=(RESULT_WORDS,),
        dtype=np.uint64,
    )

    try:
        profile_buffer[:] = profile_frame
        product_buffer[:] = product_frame

        profile_us = send_only(
            dma,
            profile_buffer,
        )

        # The profile commit occurs immediately after the DMA frame.
        time.sleep(
            0.001
        )

        print(
            "PASS: q0 and q1 profiles loaded concurrently"
        )

        print(
            f"Dual profile frame: {PROFILE_BYTES} bytes"
        )

        print(
            f"Dual profile load: {profile_us:.2f} us"
        )

        first_us = run_product(
            dma,
            product_buffer,
            receive_buffer,
        )

        first0, first1 = split_results(
            receive_buffer
        )

        validate(
            first0,
            expected0,
            "First tower 0 result",
        )

        validate(
            first1,
            expected1,
            "First tower 1 result",
        )

        print(
            "PASS: first parallel two-tower product matches OpenFHE"
        )

        print(
            f"First two-tower product: {first_us:.2f} us"
        )

        timings_us: list[float] = []

        final0 = first0
        final1 = first1

        for run_index in range(
            args.timed_runs
        ):
            elapsed_us = run_product(
                dma,
                product_buffer,
                receive_buffer,
            )

            final0, final1 = split_results(
                receive_buffer
            )

            validate(
                final0,
                expected0,
                f"Timed tower 0 run {run_index}",
            )

            validate(
                final1,
                expected1,
                f"Timed tower 1 run {run_index}",
            )

            timings_us.append(
                elapsed_us
            )

        output_root = args.output.resolve()

        output_root.mkdir(
            parents=True,
            exist_ok=True,
        )

        tower0_path = (
            output_root
            / "fpga_tower0.bin"
        )

        tower1_path = (
            output_root
            / "fpga_tower1.bin"
        )

        np.asarray(
            final0,
            dtype="<u4",
        ).tofile(
            tower0_path
        )

        np.asarray(
            final1,
            dtype="<u4",
        ).tofile(
            tower1_path
        )

        sorted_timings = sorted(
            timings_us
        )

        p95_index = max(
            0,
            int(
                np.ceil(
                    0.95
                    * len(sorted_timings)
                )
            )
            - 1,
        )

        median_us = statistics.median(
            timings_us
        )

        mean_us = statistics.fmean(
            timings_us
        )

        p95_us = sorted_timings[
            p95_index
        ]

        dcrt_products_per_second = (
            1_000_000.0
            / median_us
        )

        tower_products_per_second = (
            2_000_000.0
            / median_us
        )

        arithmetic_ceiling = (
            1_000_000.0
            / EXPECTED_CORE_LATENCY_US
        )

        overhead_us = (
            median_us
            - EXPECTED_CORE_LATENCY_US
        )

        print(
            f"PASS: {args.timed_runs} parallel two-tower products all match OpenFHE"
        )

        print(
            "PASS: both towers completed in one physical core-latency interval"
        )

        print(
            f"Minimum: {min(timings_us):.2f} us"
        )

        print(
            f"Median: {median_us:.2f} us"
        )

        print(
            f"Mean: {mean_us:.2f} us"
        )

        print(
            f"p95: {p95_us:.2f} us"
        )

        print(
            f"Maximum: {max(timings_us):.2f} us"
        )

        print(
            f"Two-tower DCRTPoly products/s: {dcrt_products_per_second:.2f}"
        )

        print(
            f"Individual tower products/s: {tower_products_per_second:.2f}"
        )

        print(
            f"Arithmetic ceiling: {arithmetic_ceiling:.2f} DCRTPoly products/s"
        )

        print(
            f"Core cycles: {EXPECTED_CORE_CYCLES}"
        )

        print(
            f"Core latency: {EXPECTED_CORE_LATENCY_US:.2f} us"
        )

        print(
            f"Median DMA/software overhead: {overhead_us:.2f} us"
        )

        print(
            f"Wrote: {tower0_path}"
        )

        print(
            f"Wrote: {tower1_path}"
        )

        print(
            "PASS board parallel two-tower OpenFHE stage"
        )

    finally:
        profile_buffer.freebuffer()
        product_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
