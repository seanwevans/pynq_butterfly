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
PROFILE_WORDS = 16_385
PRODUCT_WORDS = 8_193
RESULT_WORDS = 4_096
EXPECTED_CORE_CYCLES = 22_968
EXPECTED_CORE_LATENCY_US = 229.68
DIRECT_STREAM_LOWER_BOUND_CYCLES = PRODUCT_WORDS + EXPECTED_CORE_CYCLES + 2 * RESULT_WORDS
DIRECT_STREAM_LOWER_BOUND_US = DIRECT_STREAM_LOWER_BOUND_CYCLES / 100.0


def read_mem(path: Path, expected_words: int) -> np.ndarray:
    values = [
        int(line.strip(), 16)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if len(values) != expected_words:
        raise ValueError(f"{path}: found {len(values)} words; expected {expected_words}")
    return np.asarray(values, dtype=np.uint32)


def read_u32le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")
    if values.size != expected_words:
        raise ValueError(f"{path}: found {values.size} words; expected {expected_words}")
    return np.asarray(values, dtype=np.uint32)


def pair_words(lane0: np.ndarray, lane1: np.ndarray) -> np.ndarray:
    if lane0.shape != lane1.shape:
        raise ValueError("Lane arrays have different shapes")
    return lane0.astype(np.uint64) | (lane1.astype(np.uint64) << np.uint64(32))


def build_profile_lane(profile_directory: Path) -> tuple[np.uint32, np.uint32, np.ndarray]:
    metadata = json.loads((profile_directory / "profile.json").read_text(encoding="utf-8"))
    modulus = int(metadata["modulus"])
    reciprocal = (1 << 60) // modulus
    if reciprocal >= 1 << 31:
        raise ValueError(f"{profile_directory}: reciprocal {reciprocal} does not fit 31 bits")
    payload = np.concatenate([
        read_mem(profile_directory / "twist_factors.mem", N),
        read_mem(profile_directory / "forward_twiddles.mem", TWIDDLES),
        read_mem(profile_directory / "inverse_twiddles.mem", TWIDDLES),
        read_mem(profile_directory / "inverse_scale_factors.mem", N),
    ]).astype(np.uint32, copy=False)
    if payload.size != 16_382:
        raise RuntimeError(f"Profile payload contains {payload.size} words")
    return np.uint32(modulus), np.uint32(reciprocal), payload


def build_profile_frame(vector_root: Path) -> np.ndarray:
    modulus0, reciprocal0, payload0 = build_profile_lane(vector_root / "profile0")
    modulus1, reciprocal1, payload1 = build_profile_lane(vector_root / "profile1")
    lane0 = np.empty(PROFILE_WORDS, dtype=np.uint32)
    lane1 = np.empty(PROFILE_WORDS, dtype=np.uint32)
    lane0[0] = lane1[0] = PROFILE_COMMAND
    lane0[1], lane1[1] = modulus0, modulus1
    lane0[2], lane1[2] = reciprocal0, reciprocal1
    lane0[3:], lane1[3:] = payload0, payload1
    return pair_words(lane0, lane1)


def build_product_frame(vector_root: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    dma0 = read_u32le(vector_root / "tower0" / "dma_input.bin", 2 * N)
    dma1 = read_u32le(vector_root / "tower1" / "dma_input.bin", 2 * N)
    expected0 = read_u32le(vector_root / "tower0" / "openfhe_expected.bin", N)
    expected1 = read_u32le(vector_root / "tower1" / "openfhe_expected.bin", N)
    lane0 = np.empty(PRODUCT_WORDS, dtype=np.uint32)
    lane1 = np.empty(PRODUCT_WORDS, dtype=np.uint32)
    lane0[0] = lane1[0] = PRODUCT_COMMAND
    lane0[1:], lane1[1:] = dma0, dma1
    return pair_words(lane0, lane1), expected0, expected1


def split_results(paired: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(paired, dtype=np.uint64)
    return (
        (values & np.uint64(0xFFFFFFFF)).astype(np.uint32),
        np.right_shift(values, np.uint64(32)).astype(np.uint32),
    )


def resolve_dma(overlay: Overlay):
    names = [name for name in overlay.ip_dict if "axi_dma" in name.lower()]
    if len(names) != 1:
        raise RuntimeError(f"Expected exactly one AXI DMA; found {names}")
    return getattr(overlay, names[0])


def send_only(dma, buffer) -> float:
    buffer.flush()
    start_ns = time.perf_counter_ns()
    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()
    return (time.perf_counter_ns() - start_ns) / 1_000.0


def run_product(dma, send_buffer, receive_buffer) -> float:
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


def validate(actual: np.ndarray, expected: np.ndarray, label: str) -> None:
    if np.array_equal(actual, expected):
        return
    mismatch = int(np.flatnonzero(actual != expected)[0])
    raise AssertionError(
        f"{label} mismatch at coefficient {mismatch}: "
        f"result={int(actual[mismatch])}, expected={int(expected[mismatch])}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the four-butterfly two-tower multiplier on PYNQ-Z2.")
    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--timed-runs", type=int, default=20)
    args = parser.parse_args()
    if args.timed_runs < 1:
        parser.error("--timed-runs must be positive")

    vector_root = args.vectors.resolve()
    profile_frame = build_profile_frame(vector_root)
    product_frame, expected0, expected1 = build_product_frame(vector_root)

    overlay = Overlay(str(args.overlay.resolve()), download=True)
    dma = resolve_dma(overlay)

    profile_buffer = allocate(shape=(PROFILE_WORDS,), dtype=np.uint64)
    product_buffer = allocate(shape=(PRODUCT_WORDS,), dtype=np.uint64)
    receive_buffer = allocate(shape=(RESULT_WORDS,), dtype=np.uint64)

    try:
        profile_buffer[:] = profile_frame
        product_buffer[:] = product_frame
        profile_us = send_only(dma, profile_buffer)
        time.sleep(0.001)
        print("PASS: q0 and q1 profiles loaded concurrently")
        print(f"Dual profile frame: {PROFILE_WORDS * 8} bytes")
        print(f"Dual profile load: {profile_us:.2f} us")

        first_us = run_product(dma, product_buffer, receive_buffer)
        first0, first1 = split_results(receive_buffer)
        validate(first0, expected0, "First tower 0 result")
        validate(first1, expected1, "First tower 1 result")
        print("PASS: first two-tower product matches OpenFHE")
        print(f"First two-tower product: {first_us:.2f} us")

        timings_us: list[float] = []
        for run_index in range(args.timed_runs):
            elapsed_us = run_product(dma, product_buffer, receive_buffer)
            actual0, actual1 = split_results(receive_buffer)
            validate(actual0, expected0, f"Timed tower 0 run {run_index}")
            validate(actual1, expected1, f"Timed tower 1 run {run_index}")
            timings_us.append(elapsed_us)

        median_us = statistics.median(timings_us)
        print("PASS: every timed result matches OpenFHE")
        print(f"Core arithmetic: {EXPECTED_CORE_CYCLES} cycles, {EXPECTED_CORE_LATENCY_US:.2f} us")
        print(f"Direct-stream lower bound: {DIRECT_STREAM_LOWER_BOUND_CYCLES} cycles, {DIRECT_STREAM_LOWER_BOUND_US:.2f} us")
        print(f"Physical median: {median_us:.2f} us")
        print(f"Physical min/max: {min(timings_us):.2f} / {max(timings_us):.2f} us")
        print(f"Physical throughput: {1_000_000.0 / median_us:.2f} two-tower products/s")
    finally:
        profile_buffer.freebuffer()
        product_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
