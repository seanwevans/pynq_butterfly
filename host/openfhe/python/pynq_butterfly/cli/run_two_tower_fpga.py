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

PROFILE_WORDS = 16384
PRODUCT_WORDS = 8193
RESULT_WORDS = 4096


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


def build_profile_frame(profile_dir: Path) -> np.ndarray:
    metadata = json.loads(
        (profile_dir / "profile.json").read_text(encoding="utf-8")
    )

    frame = np.empty(PROFILE_WORDS, dtype=np.uint32)
    cursor = 0

    frame[cursor] = PROFILE_COMMAND
    cursor += 1

    frame[cursor] = np.uint32(metadata["modulus"])
    cursor += 1

    for filename, count in (
        ("twist_factors.mem", N),
        ("forward_twiddles.mem", TWIDDLES),
        ("inverse_twiddles.mem", TWIDDLES),
        ("inverse_scale_factors.mem", N),
    ):
        values = read_mem(profile_dir / filename, count)
        frame[cursor : cursor + count] = values
        cursor += count

    if cursor != PROFILE_WORDS:
        raise RuntimeError("Profile frame length mismatch")

    return frame


def build_product_frame(tower_dir: Path) -> tuple[np.ndarray, np.ndarray]:
    dma_input = read_u32le(
        tower_dir / "dma_input.bin",
        2 * N,
    )

    expected = read_u32le(
        tower_dir / "openfhe_expected.bin",
        N,
    )

    frame = np.empty(PRODUCT_WORDS, dtype=np.uint32)
    frame[0] = PRODUCT_COMMAND
    frame[1:] = dma_input

    return frame, expected


def resolve_dma(overlay: Overlay):
    names = [
        name
        for name in overlay.ip_dict
        if "axi_dma" in name.lower()
    ]

    if len(names) != 1:
        raise RuntimeError(f"Expected one AXI DMA; found {names}")

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


def validate(actual, expected: np.ndarray, label: str) -> None:
    actual_array = np.asarray(actual, dtype=np.uint32)

    if np.array_equal(actual_array, expected):
        return

    mismatch = int(np.flatnonzero(actual_array != expected)[0])

    raise AssertionError(
        f"{label} mismatch at coefficient {mismatch}: "
        f"result={int(actual_array[mismatch])}, "
        f"expected={int(expected[mismatch])}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("."))
    parser.add_argument("--timed-runs", type=int, default=5)

    args = parser.parse_args()

    overlay = Overlay(str(args.overlay.resolve()), download=True)
    dma = resolve_dma(overlay)

    output_dir = args.output.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    profile_buffer = allocate(
        shape=(PROFILE_WORDS,),
        dtype=np.uint32,
    )

    product_buffer = allocate(
        shape=(PRODUCT_WORDS,),
        dtype=np.uint32,
    )

    receive_buffer = allocate(
        shape=(RESULT_WORDS,),
        dtype=np.uint32,
    )

    try:
        for tower_index in range(2):
            profile_dir = (
                args.vectors.resolve()
                / f"profile{tower_index}"
            )

            tower_dir = (
                args.vectors.resolve()
                / f"tower{tower_index}"
            )

            profile_frame = build_profile_frame(profile_dir)
            product_frame, expected = build_product_frame(tower_dir)

            profile_buffer[:] = profile_frame
            product_buffer[:] = product_frame

            profile_us = send_only(dma, profile_buffer)
            time.sleep(0.001)

            first_us = run_product(
                dma,
                product_buffer,
                receive_buffer,
            )

            validate(
                receive_buffer,
                expected,
                f"Tower {tower_index} first product",
            )

            timings: list[float] = []

            for run_index in range(args.timed_runs):
                elapsed_us = run_product(
                    dma,
                    product_buffer,
                    receive_buffer,
                )

                validate(
                    receive_buffer,
                    expected,
                    f"Tower {tower_index} run {run_index}",
                )

                timings.append(elapsed_us)

            result_path = (
                output_dir
                / f"fpga_tower{tower_index}.bin"
            )

            np.asarray(
                receive_buffer,
                dtype="<u4",
            ).tofile(result_path)

            print(
                f"PASS: tower {tower_index} profile loaded at runtime"
            )

            print(
                f"Tower {tower_index} profile load: {profile_us:.2f} us"
            )

            print(
                f"Tower {tower_index} first product: {first_us:.2f} us"
            )

            print(
                f"PASS: tower {tower_index} "
                f"{args.timed_runs} timed products all match OpenFHE"
            )

            print(
                f"Tower {tower_index} median: "
                f"{statistics.median(timings):.2f} us"
            )

            print(
                f"Wrote: {result_path}"
            )

        print(
            "PASS: one physical core executed two OpenFHE RNS towers"
        )

        print(
            "PASS board two-tower runtime-profile stage"
        )

    finally:
        profile_buffer.freebuffer()
        product_buffer.freebuffer()
        receive_buffer.freebuffer()


if __name__ == "__main__":
    main()
