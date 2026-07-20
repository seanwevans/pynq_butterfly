#!/usr/bin/env python3

from __future__ import annotations

import argparse
import statistics
import time
from pathlib import Path

import numpy as np
from pynq import Overlay, allocate


N = 4096
COMPACT_TWIDDLE_WORDS = 4095

PROFILE_COMMAND = np.uint32(0x50524F46)
PRODUCT_COMMAND = np.uint32(0x4D554C31)

PROFILE_MODULUS = np.uint32(1_073_692_673)

PROFILE_FRAME_WORDS = 16_384
PROFILE_FRAME_BYTES = 65_536

PRODUCT_INPUT_WORDS = 8_193
PRODUCT_INPUT_BYTES = 32_772

PRODUCT_OUTPUT_WORDS = 4_096
PRODUCT_OUTPUT_BYTES = 16_384

EXPECTED_CORE_CYCLES = 1_339_394
EXPECTED_CORE_LATENCY_US = 13_393.94


def read_mem(
    path: Path,
    expected_words: int,
) -> np.ndarray:
    values: list[int] = []

    with path.open(
        "r",
        encoding="utf-8",
    ) as handle:
        for line_number, raw_line in enumerate(
            handle,
            start=1,
        ):
            line = raw_line.strip()

            if not line:
                continue

            try:
                value = int(
                    line,
                    16,
                )
            except ValueError as exc:
                raise ValueError(
                    f"{path}:{line_number}: "
                    f"invalid hexadecimal word {line!r}"
                ) from exc

            if not 0 <= value <= 0xFFFFFFFF:
                raise ValueError(
                    f"{path}:{line_number}: "
                    f"word is outside uint32"
                )

            values.append(
                value
            )

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


def build_profile_frame(
    profile_directory: Path,
) -> np.ndarray:
    twist = read_mem(
        profile_directory
        / "twist_factors.mem",
        N,
    )

    forward = read_mem(
        profile_directory
        / "forward_twiddles.mem",
        COMPACT_TWIDDLE_WORDS,
    )

    inverse = read_mem(
        profile_directory
        / "inverse_twiddles.mem",
        COMPACT_TWIDDLE_WORDS,
    )

    inverse_scale = read_mem(
        profile_directory
        / "inverse_scale_factors.mem",
        N,
    )

    frame = np.empty(
        PROFILE_FRAME_WORDS,
        dtype=np.uint32,
    )

    cursor = 0

    frame[cursor] = PROFILE_COMMAND
    cursor += 1

    frame[cursor] = PROFILE_MODULUS
    cursor += 1

    frame[cursor : cursor + N] = twist
    cursor += N

    frame[
        cursor
        : cursor + COMPACT_TWIDDLE_WORDS
    ] = forward

    cursor += COMPACT_TWIDDLE_WORDS

    frame[
        cursor
        : cursor + COMPACT_TWIDDLE_WORDS
    ] = inverse

    cursor += COMPACT_TWIDDLE_WORDS

    frame[cursor : cursor + N] = inverse_scale
    cursor += N

    if cursor != PROFILE_FRAME_WORDS:
        raise RuntimeError(
            f"Profile construction ended at word {cursor}; "
            f"expected {PROFILE_FRAME_WORDS}"
        )

    return frame


def build_product_frame(
    vector_directory: Path,
) -> tuple[np.ndarray, np.ndarray]:
    dma_input = read_u32le(
        vector_directory
        / "dma_input.bin",
        2 * N,
    )

    expected = read_u32le(
        vector_directory
        / "openfhe_expected.bin",
        N,
    )

    frame = np.empty(
        PRODUCT_INPUT_WORDS,
        dtype=np.uint32,
    )

    frame[0] = PRODUCT_COMMAND
    frame[1:] = dma_input

    return frame, expected


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


def send_only(
    dma,
    send_buffer,
) -> float:
    send_buffer.flush()

    start_ns = time.perf_counter_ns()

    dma.sendchannel.transfer(
        send_buffer
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
            "Load an N=4096 arithmetic profile at runtime, "
            "then execute OpenFHE-generated tower products "
            "through the PYNQ-Z2 DMA overlay."
        )
    )

    parser.add_argument(
        "--overlay",
        type=Path,
        default=Path(
            "poly_mul4096_runtime_profile_dma.bit"
        ),
    )

    parser.add_argument(
        "--profile",
        type=Path,
        default=Path("."),
        help=(
            "Directory containing twist_factors.mem, "
            "forward_twiddles.mem, inverse_twiddles.mem, "
            "and inverse_scale_factors.mem."
        ),
    )

    parser.add_argument(
        "--vectors",
        type=Path,
        default=Path("."),
        help=(
            "Directory containing dma_input.bin and "
            "openfhe_expected.bin."
        ),
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=Path(
            "runtime_profile_fpga_result.bin"
        ),
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

    profile_frame = build_profile_frame(
        args.profile.resolve()
    )

    product_frame, expected = build_product_frame(
        args.vectors.resolve()
    )

    overlay = Overlay(
        str(args.overlay.resolve()),
        download=True,
    )

    dma = resolve_dma(
        overlay
    )

    profile_buffer = allocate(
        shape=(PROFILE_FRAME_WORDS,),
        dtype=np.uint32,
    )

    product_buffer = allocate(
        shape=(PRODUCT_INPUT_WORDS,),
        dtype=np.uint32,
    )

    receive_buffer = allocate(
        shape=(PRODUCT_OUTPUT_WORDS,),
        dtype=np.uint32,
    )

    try:
        profile_buffer[:] = profile_frame
        product_buffer[:] = product_frame

        profile_elapsed_us = send_only(
            dma,
            profile_buffer,
        )

        # The streamed TLAST is accepted one clock before the wrapper
        # pulses profile_commit. A millisecond is negligible as a
        # one-time profile cost and makes the software/core boundary
        # unambiguous.
        time.sleep(
            0.001
        )

        print(
            "PASS: runtime q0 profile streamed to FPGA"
        )

        print(
            f"Profile frame: {PROFILE_FRAME_BYTES} bytes"
        )

        print(
            f"Profile load elapsed: {profile_elapsed_us:.2f} us"
        )

        first_elapsed_us = run_product(
            dma,
            product_buffer,
            receive_buffer,
        )

        validate(
            receive_buffer,
            expected,
            "First runtime-profile OpenFHE product",
        )

        print(
            "PASS: first runtime-profile FPGA product matches OpenFHE"
        )

        print(
            f"First product elapsed: {first_elapsed_us:.2f} us"
        )

        timings_us: list[float] = []

        for run_index in range(
            args.timed_runs
        ):
            elapsed_us = run_product(
                dma,
                product_buffer,
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
        ).tofile(
            output_path
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

        throughput = (
            1_000_000.0
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
            f"PASS: {args.timed_runs} timed products all match OpenFHE"
        )

        print(
            "PASS: one runtime-loaded profile supports repeated products"
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
            f"Median DMA/software overhead: {overhead_us:.2f} us"
        )

        print(
            f"Wrote FPGA result: {output_path}"
        )

        print(
            "PASS end to end runtime-profile OpenFHE bridge"
        )

    finally:
        profile_buffer.freebuffer()
        product_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
