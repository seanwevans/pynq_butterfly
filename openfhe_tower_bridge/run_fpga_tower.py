#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

import numpy as np
from pynq import Overlay, allocate


RING_DIMENSION = 4096
DMA_INPUT_WORDS = 8192
RESULT_WORDS = 4096

EXPECTED_CORE_CYCLES = 1_339_394
EXPECTED_CORE_LATENCY_US = 13_393.94


def read_u32le(
    path: Path,
    expected_words: int,
) -> np.ndarray:
    data = np.fromfile(
        path,
        dtype="<u4",
    )

    if data.size != expected_words:
        raise ValueError(
            f"{path}: found {data.size} words; "
            f"expected {expected_words}"
        )

    return np.asarray(
        data,
        dtype=np.uint32,
    )


def resolve_dma(overlay: Overlay):
    candidates = [
        name
        for name in overlay.ip_dict
        if "axi_dma" in name.lower()
    ]

    if len(candidates) != 1:
        raise RuntimeError(
            "Expected exactly one AXI DMA; "
            f"found {candidates}"
        )

    return getattr(
        overlay,
        candidates[0],
    )


def run_transfer(
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
    actual,
    expected: np.ndarray,
    label: str,
) -> None:
    actual_array = np.asarray(
        actual,
        dtype=np.uint32,
    )

    if np.array_equal(
        actual_array,
        expected,
    ):
        return

    mismatch_indices = np.flatnonzero(
        actual_array != expected
    )

    first_index = int(
        mismatch_indices[0]
    )

    raise AssertionError(
        f"{label} mismatch at coefficient "
        f"{first_index}: "
        f"result={int(actual_array[first_index])}, "
        f"expected={int(expected[first_index])}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Run an OpenFHE-generated one-tower DCRTPoly "
            "product through the PYNQ-Z2 N=4096 DMA overlay."
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
        default=Path("fpga_result.bin"),
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

    vector_directory = (
        args.vectors.resolve()
    )

    metadata_path = (
        vector_directory
        / "metadata.json"
    )

    metadata = json.loads(
        metadata_path.read_text(
            encoding="utf-8"
        )
    )

    if metadata["ring_dimension"] != RING_DIMENSION:
        raise ValueError(
            "Metadata ring dimension does not match the overlay"
        )

    if metadata["modulus"] != 1_073_692_673:
        raise ValueError(
            "Metadata modulus does not match the overlay"
        )

    dma_input = read_u32le(
        vector_directory
        / "dma_input.bin",
        DMA_INPUT_WORDS,
    )

    expected = read_u32le(
        vector_directory
        / "openfhe_expected.bin",
        RESULT_WORDS,
    )

    overlay = Overlay(
        str(args.overlay.resolve()),
        download=True,
    )

    dma = resolve_dma(overlay)

    send_buffer = allocate(
        shape=(DMA_INPUT_WORDS,),
        dtype=np.uint32,
    )

    receive_buffer = allocate(
        shape=(RESULT_WORDS,),
        dtype=np.uint32,
    )

    try:
        send_buffer[:] = dma_input

        first_elapsed_us = run_transfer(
            dma,
            send_buffer,
            receive_buffer,
        )

        validate(
            receive_buffer,
            expected,
            "First OpenFHE tower product",
        )

        print(
            "PASS: first FPGA product matches OpenFHE"
        )

        print(
            f"First elapsed: {first_elapsed_us:.2f} us"
        )

        timings_us: list[float] = []

        for run_index in range(
            args.timed_runs
        ):
            elapsed_us = run_transfer(
                dma,
                send_buffer,
                receive_buffer,
            )

            validate(
                receive_buffer,
                expected,
                f"Timed run {run_index}",
            )

            timings_us.append(
                elapsed_us
            )

        output_path = (
            args.output.resolve()
        )

        output_path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        np.asarray(
            receive_buffer,
            dtype="<u4",
        ).tofile(output_path)

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

        throughput = (
            1_000_000.0
            / median_us
        )

        arithmetic_ceiling = (
            1_000_000.0
            / EXPECTED_CORE_LATENCY_US
        )

        print(
            f"PASS: {args.timed_runs} timed OpenFHE tower products all match"
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
            f"Median products/s: {throughput:.2f}"
        )

        print(
            f"Arithmetic ceiling: {arithmetic_ceiling:.2f} products/s"
        )

        print(
            f"Core cycles: {EXPECTED_CORE_CYCLES}"
        )

        print(
            f"Core latency: {EXPECTED_CORE_LATENCY_US:.2f} us"
        )

        print(
            "Wrote FPGA result: "
            f"{output_path}"
        )

        print(
            "PASS FPGA stage"
        )

    finally:
        send_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
