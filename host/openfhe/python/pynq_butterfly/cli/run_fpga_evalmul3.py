#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from pynq import Overlay, allocate


N = 4096

PROFILE_COMMAND = np.uint32(0x45565046)  # EVPF
BATCH_COMMAND = np.uint32(0x45564233)    # EVB3

PROFILE_WORDS = 3
INPUT_WORDS_PER_COEFFICIENT = 4
OUTPUT_WORDS_PER_COEFFICIENT = 3

CLOCK_HZ = 100_000_000
IDEAL_PAIR_CYCLES_PER_CIPHERTEXT = 4 * N


@dataclass(frozen=True)
class ProfileKey:
    modulus0: int
    mu0: int
    modulus1: int
    mu1: int


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def tower_name(index: int) -> str:
    return f"tower{index:03d}"


def read_u32le(path: Path, expected_words: int) -> np.ndarray:
    values = np.fromfile(path, dtype="<u4")

    if values.size != expected_words:
        raise ValueError(
            f"{path}: found {values.size} words; expected {expected_words}"
        )

    return np.asarray(values, dtype=np.uint32)


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


def build_profile_frame(
    tower0: Path,
    tower1: Path,
) -> tuple[ProfileKey, np.ndarray]:
    modulus0, mu0 = load_profile(tower0)
    modulus1, mu1 = load_profile(tower1)

    key = ProfileKey(modulus0, mu0, modulus1, mu1)

    lane0 = np.asarray(
        [PROFILE_COMMAND, modulus0, mu0],
        dtype=np.uint32,
    )

    lane1 = np.asarray(
        [PROFILE_COMMAND, modulus1, mu1],
        dtype=np.uint32,
    )

    return key, pair_words(lane0, lane1)


def build_batch_frame(
    dma0: np.ndarray,
    dma1: np.ndarray,
    ciphertext_count: int,
) -> np.ndarray:
    expected_words = (
        ciphertext_count
        * N
        * INPUT_WORDS_PER_COEFFICIENT
    )

    if dma0.size != expected_words or dma1.size != expected_words:
        raise ValueError("Input tower length does not match metadata")

    lane0 = np.empty(2 + expected_words, dtype=np.uint32)
    lane1 = np.empty(2 + expected_words, dtype=np.uint32)

    lane0[0] = BATCH_COMMAND
    lane1[0] = BATCH_COMMAND
    lane0[1] = np.uint32(ciphertext_count)
    lane1[1] = np.uint32(ciphertext_count)
    lane0[2:] = dma0
    lane1[2:] = dma1

    return pair_words(lane0, lane1)


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


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Benchmark fused OpenFHE evaluation-domain ciphertext "
            "multiplication on a PYNQ overlay containing EVPF/EVB3."
        )
    )

    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--timed-runs", type=int, default=3)
    parser.add_argument(
        "--ciphertexts",
        type=int,
        default=None,
        help=(
            "Use only the first N ciphertexts from a larger vector set. "
            "The vector files remain unchanged."
        ),
    )

    args = parser.parse_args()

    if args.timed_runs < 1:
        parser.error("--timed-runs must be positive")

    vector_root = args.vectors.resolve()
    result_root = args.results.resolve()
    metadata = read_json(vector_root / "metadata.json")

    tower_count = int(metadata["tower_count"])
    available_ciphertext_count = int(metadata["ciphertext_count"])
    ring_dimension = int(metadata["ring_dimension"])

    if ring_dimension != N:
        raise ValueError(f"Overlay requires N={N}")

    ciphertext_count = (
        available_ciphertext_count
        if args.ciphertexts is None
        else args.ciphertexts
    )

    if ciphertext_count < 1:
        parser.error("--ciphertexts must be positive")

    if ciphertext_count > available_ciphertext_count:
        parser.error(
            "--ciphertexts exceeds the vector-set ciphertext count "
            f"({available_ciphertext_count})"
        )

    pair_count = (tower_count + 1) // 2

    input_words = (
        ciphertext_count
        * N
        * INPUT_WORDS_PER_COEFFICIENT
    )

    output_words = (
        ciphertext_count
        * N
        * OUTPUT_WORDS_PER_COEFFICIENT
    )

    result_root.mkdir(parents=True, exist_ok=True)

    overlay_path = args.overlay.resolve()

    if overlay_path.with_suffix(".xsa").exists():
        raise RuntimeError(
            "Rename the same-stem XSA before loading the PYNQ overlay"
        )

    overlay = Overlay(str(overlay_path), download=True)
    dma = resolve_dma(overlay)

    total_profile_us = 0.0
    total_pair_us = 0.0
    verified_tower_components = 0

    print(
        "Evaluation-domain ciphertext batch: "
        f"towers={tower_count}, pairs={pair_count}, "
        f"ciphertexts={ciphertext_count}, "
        f"available={available_ciphertext_count}"
    )

    print(
        "pair  towers       profile_us  median_us  "
        "us/ciphertext  efficiency"
    )

    for pair_index in range(pair_count):
        tower0 = 2 * pair_index
        tower1_real = tower0 + 1 < tower_count
        tower1 = tower0 + 1 if tower1_real else tower0

        name0 = tower_name(tower0)
        name1 = tower_name(tower1)

        key, profile_frame = build_profile_frame(
            vector_root / name0,
            vector_root / name1,
        )

        profile_buffer = allocate(
            shape=(PROFILE_WORDS,),
            dtype=np.uint64,
        )

        try:
            require_aligned_buffer(
                profile_buffer,
                "profile buffer",
            )

            profile_buffer[:] = profile_frame
            profile_us = send_only(dma, profile_buffer)
            time.sleep(0.001)
        finally:
            profile_buffer.freebuffer()

        dma0 = read_u32le_prefix(
            vector_root / name0 / "dma_input.bin",
            input_words,
        )

        dma1 = read_u32le_prefix(
            vector_root / name1 / "dma_input.bin",
            input_words,
        )

        expected0 = read_u32le_prefix(
            vector_root / name0 / "openfhe_expected.bin",
            output_words,
        )

        expected1 = read_u32le_prefix(
            vector_root / name1 / "openfhe_expected.bin",
            output_words,
        )

        frame = build_batch_frame(dma0, dma1, ciphertext_count)

        send_buffer = allocate(shape=frame.shape, dtype=np.uint64)
        receive_buffer = allocate(shape=(output_words,), dtype=np.uint64)

        try:
            require_aligned_buffer(
                send_buffer,
                "send buffer",
            )

            require_aligned_buffer(
                receive_buffer,
                "receive buffer",
            )

            send_buffer[:] = frame

            warmup_us = run_frame(dma, send_buffer, receive_buffer)
            warm0, warm1 = split_words(receive_buffer)

            require_equal(warm0, expected0, f"pair {pair_index} warmup lane0")
            require_equal(warm1, expected1, f"pair {pair_index} warmup lane1")

            timings: list[float] = []
            actual0 = warm0
            actual1 = warm1

            for run_index in range(args.timed_runs):
                elapsed_us = run_frame(dma, send_buffer, receive_buffer)
                actual0, actual1 = split_words(receive_buffer)

                require_equal(
                    actual0,
                    expected0,
                    f"pair {pair_index} run {run_index} lane0",
                )

                require_equal(
                    actual1,
                    expected1,
                    f"pair {pair_index} run {run_index} lane1",
                )

                timings.append(elapsed_us)

            write_u32le(result_root / f"{name0}.bin", actual0)
            verified_tower_components += ciphertext_count * 3

            if tower1_real:
                write_u32le(result_root / f"{name1}.bin", actual1)
                verified_tower_components += ciphertext_count * 3

            median_us = statistics.median(timings)
            ideal_us = (
                ciphertext_count
                * IDEAL_PAIR_CYCLES_PER_CIPHERTEXT
                / CLOCK_HZ
                * 1_000_000.0
            )

            efficiency = ideal_us / median_us
            towers_label = (
                f"{tower0},{tower1}"
                if tower1_real
                else f"{tower0},dup"
            )

            print(
                f"{pair_index:4d}  {towers_label:10s}  "
                f"{profile_us:10.2f}  {median_us:9.2f}  "
                f"{median_us / ciphertext_count:13.2f}  "
                f"{efficiency:10.1%}"
            )

            print(
                "      PASS exact; "
                f"warmup={warmup_us:.2f} us; "
                "runs=" + ",".join(f"{value:.2f}" for value in timings)
            )

            total_profile_us += profile_us
            total_pair_us += median_us
        finally:
            send_buffer.freebuffer()
            receive_buffer.freebuffer()

    compute_us_per_ciphertext = total_pair_us / ciphertext_count
    end_to_end_us_per_ciphertext = (
        total_pair_us + total_profile_us
    ) / ciphertext_count

    compute_rate = 1_000_000.0 / compute_us_per_ciphertext
    end_to_end_rate = 1_000_000.0 / end_to_end_us_per_ciphertext

    print()
    print("PASS: every fused evaluation-domain component matches OpenFHE")
    print(f"verified_tower_components={verified_tower_components}")
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
