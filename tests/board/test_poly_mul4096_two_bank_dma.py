#!/usr/bin/env python3

from __future__ import annotations

import argparse
import statistics
import time
from pathlib import Path

import numpy as np

import overlay_constants
from pynq import Overlay, allocate


N = overlay_constants.N
INPUT_WORDS = 2 * N
OUTPUT_WORDS = N

EXPECTED_CORE_CYCLES = overlay_constants.SINGLE_BUTTERFLY_CORE_CYCLES
EXPECTED_CORE_LATENCY_US = 13_393.94


def read_mem(path: Path, expected_words: int) -> np.ndarray:
    values: list[int] = []

    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()

            if not line:
                continue

            try:
                values.append(int(line, 16))
            except ValueError as exc:
                raise ValueError(
                    f"{path}:{line_number}: invalid hexadecimal word {line!r}"
                ) from exc

    if len(values) != expected_words:
        raise ValueError(
            f"{path}: found {len(values)} words, expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


def resolve_dma(overlay: Overlay):
    candidates = [
        name
        for name in overlay.ip_dict
        if "axi_dma" in name.lower()
    ]

    if len(candidates) != 1:
        raise RuntimeError(
            "Expected exactly one AXI DMA in the overlay; "
            f"found {candidates}"
        )

    return getattr(overlay, candidates[0])


def run_transfer(
    dma,
    send_buffer,
    receive_buffer,
) -> float:
    receive_buffer[:] = 0

    receive_buffer.flush()
    send_buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.recvchannel.transfer(receive_buffer)
    dma.sendchannel.transfer(send_buffer)

    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_us = (
        time.perf_counter_ns() - start_ns
    ) / 1_000.0

    receive_buffer.invalidate()

    return elapsed_us


def validate_result(
    receive_buffer,
    expected: np.ndarray,
    label: str,
) -> None:
    result = np.asarray(receive_buffer)

    if np.array_equal(result, expected):
        return

    mismatch_indices = np.flatnonzero(
        result != expected
    )

    first_index = int(mismatch_indices[0])

    raise AssertionError(
        f"{label} mismatch: "
        f"index={first_index}, "
        f"result={int(result[first_index])}, "
        f"expected={int(expected[first_index])}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Validate and benchmark the PYNQ-Z2 consolidated "
            "two-bank N=4096 polynomial-multiplier DMA overlay."
        )
    )

    parser.add_argument(
        "--overlay",
        type=Path,
        default=Path("poly_mul4096_two_bank_dma.bit"),
    )

    parser.add_argument(
        "--vectors",
        type=Path,
        default=Path("."),
        help=(
            "Directory containing input_a.mem, input_b.mem, "
            "and convolution.mem."
        ),
    )

    parser.add_argument(
        "--timed-runs",
        type=int,
        default=20,
    )

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error("--timed-runs must be positive")

    overlay_path = args.overlay.resolve()
    vectors_path = args.vectors.resolve()

    input_a = read_mem(
        vectors_path / "input_a.mem",
        N,
    )

    input_b = read_mem(
        vectors_path / "input_b.mem",
        N,
    )

    expected = read_mem(
        vectors_path / "convolution.mem",
        N,
    )

    overlay = Overlay(
        str(overlay_path),
        download=True,
    )

    dma = resolve_dma(overlay)

    send_buffer = allocate(
        shape=(INPUT_WORDS,),
        dtype=np.uint32,
    )

    receive_buffer = allocate(
        shape=(OUTPUT_WORDS,),
        dtype=np.uint32,
    )

    try:
        send_buffer[:N] = input_a
        send_buffer[N:] = input_b

        first_elapsed_us = run_transfer(
            dma,
            send_buffer,
            receive_buffer,
        )

        validate_result(
            receive_buffer,
            expected,
            "First DMA product",
        )

        print(
            "PASS: first two-bank N=4096 DMA product matches golden convolution"
        )

        print(
            f"First elapsed: {first_elapsed_us:.2f} us"
        )

        timings_us: list[float] = []

        for run_index in range(args.timed_runs):
            elapsed_us = run_transfer(
                dma,
                send_buffer,
                receive_buffer,
            )

            validate_result(
                receive_buffer,
                expected,
                f"Timed run {run_index}",
            )

            timings_us.append(elapsed_us)

        sorted_timings = sorted(timings_us)

        p95_index = max(
            0,
            int(np.ceil(0.95 * len(sorted_timings))) - 1,
        )

        median_us = statistics.median(
            timings_us
        )

        mean_us = statistics.fmean(
            timings_us
        )

        p95_us = sorted_timings[p95_index]

        overhead_us = (
            median_us
            - EXPECTED_CORE_LATENCY_US
        )

        products_per_second = (
            1_000_000.0
            / median_us
        )

        arithmetic_ceiling = (
            1_000_000.0
            / EXPECTED_CORE_LATENCY_US
        )

        ceiling_fraction = (
            products_per_second
            / arithmetic_ceiling
        )

        print(
            f"PASS: {args.timed_runs} timed two-bank DMA products all match"
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
            f"Median products/s: {products_per_second:.2f}"
        )

        print(
            f"Arithmetic ceiling: {arithmetic_ceiling:.2f} products/s"
        )

        print(
            f"Fraction of arithmetic ceiling: {100.0 * ceiling_fraction:.2f}%"
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
            "PASS end to end"
        )

    finally:
        send_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
