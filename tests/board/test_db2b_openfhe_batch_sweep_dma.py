#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import statistics
import time
from pathlib import Path

import numpy as np

import overlay_constants
from pynq import Overlay, allocate


N = overlay_constants.N
TWIDDLES = overlay_constants.TWIDDLE_WORDS
WORDS_PER_PRODUCT_INPUT = 2 * N
WORDS_PER_PRODUCT_OUTPUT = N

PROFILE_COMMAND = np.uint32(overlay_constants.PROFILE_COMMAND_WORD)
BATCH_COMMAND = np.uint32(overlay_constants.BATCH_COMMAND_WORD)
PROFILE_WORDS = 16_384
PROFILE_BYTES = 131_072
PER_PRODUCT_CORE_CYCLES = overlay_constants.DUAL_BUTTERFLY_CORE_CYCLES
WRITE_DRAIN_CYCLES_PER_PRODUCT = 1
CLOCK_MHZ = 100.0
DEFAULT_BATCH_COUNTS = (1, 2, 4, 8, 16)
DEFAULT_OPENFHE_REFERENCE_US = 7_161.35
DEFAULT_SINGLE_FPGA_REFERENCE_US = 7_186.59


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
    return lane0.astype(np.uint64) | (
        lane1.astype(np.uint64) << np.uint64(32)
    )


def build_profile_lane(profile_directory: Path) -> tuple[np.uint32, np.ndarray]:
    metadata = json.loads(
        (profile_directory / "profile.json").read_text(encoding="utf-8")
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
        raise RuntimeError(f"Profile payload contains {payload.size} words")
    return np.uint32(metadata["modulus"]), payload


def build_profile_frame(vector_root: Path) -> np.ndarray:
    product0 = vector_root / "product0"
    modulus0, payload0 = build_profile_lane(product0 / "profile0")
    modulus1, payload1 = build_profile_lane(product0 / "profile1")

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
        WORDS_PER_PRODUCT_INPUT,
    )
    dma1 = read_u32le(
        product_root / "tower1" / "dma_input.bin",
        WORDS_PER_PRODUCT_INPUT,
    )
    expected0 = read_u32le(
        product_root / "tower0" / "openfhe_expected.bin",
        WORDS_PER_PRODUCT_OUTPUT,
    )
    expected1 = read_u32le(
        product_root / "tower1" / "openfhe_expected.bin",
        WORDS_PER_PRODUCT_OUTPUT,
    )
    return dma0, dma1, expected0, expected1


def load_products(
    vector_root: Path,
    product_count: int,
) -> list[tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]]:
    products = []
    for product_index in range(product_count):
        product_root = vector_root / f"product{product_index}"
        if not product_root.is_dir():
            raise FileNotFoundError(product_root)
        products.append(read_product(product_root))
    return products


def build_batch_frame(
    products: list[tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]],
    batch_count: int,
) -> tuple[np.ndarray, list[tuple[np.ndarray, np.ndarray]]]:
    input_words = 2 + batch_count * WORDS_PER_PRODUCT_INPUT
    lane0 = np.empty(input_words, dtype=np.uint32)
    lane1 = np.empty(input_words, dtype=np.uint32)
    lane0[0] = BATCH_COMMAND
    lane1[0] = BATCH_COMMAND
    lane0[1] = np.uint32(batch_count)
    lane1[1] = np.uint32(batch_count)

    expected: list[tuple[np.ndarray, np.ndarray]] = []
    cursor = 2

    for product_index in range(batch_count):
        dma0, dma1, expected0, expected1 = products[product_index]
        stop = cursor + WORDS_PER_PRODUCT_INPUT
        lane0[cursor:stop] = dma0
        lane1[cursor:stop] = dma1
        expected.append((expected0, expected1))
        cursor = stop

    if cursor != input_words:
        raise RuntimeError("Batch input frame length mismatch")

    return pair_words(lane0, lane1), expected


def split_results(paired: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    values = np.asarray(paired, dtype=np.uint64)
    lane0 = (values & np.uint64(0xFFFFFFFF)).astype(np.uint32)
    lane1 = np.right_shift(values, np.uint64(32)).astype(np.uint32)
    return lane0, lane1


def validate_batch(
    paired: np.ndarray,
    expected: list[tuple[np.ndarray, np.ndarray]],
    label: str,
) -> tuple[np.ndarray, np.ndarray]:
    lane0, lane1 = split_results(paired)

    for product_index, (expected0, expected1) in enumerate(expected):
        start = product_index * WORDS_PER_PRODUCT_OUTPUT
        stop = start + WORDS_PER_PRODUCT_OUTPUT

        for tower_index, actual, wanted in (
            (0, lane0[start:stop], expected0),
            (1, lane1[start:stop], expected1),
        ):
            if np.array_equal(actual, wanted):
                continue
            mismatch = int(np.flatnonzero(actual != wanted)[0])
            raise AssertionError(
                f"{label}: product {product_index}, tower {tower_index}, "
                f"coefficient {mismatch}: result={int(actual[mismatch])}, "
                f"expected={int(wanted[mismatch])}"
            )

    return lane0, lane1


def resolve_dma(overlay: Overlay):
    names = [name for name in overlay.ip_dict if "dma" in name.lower()]
    if len(names) != 1:
        raise RuntimeError(f"Expected exactly one DMA; found {names}")
    return getattr(overlay, names[0])


def send_only(dma, buffer) -> float:
    buffer.flush()
    start_ns = time.perf_counter_ns()
    dma.sendchannel.transfer(buffer)
    dma.sendchannel.wait()
    return (time.perf_counter_ns() - start_ns) / 1_000.0


def run_batch(dma, send_buffer, receive_buffer) -> float:
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


def percentile_nearest_rank(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = max(0, int(np.ceil(fraction * len(ordered))) - 1)
    return ordered[index]


def summarize_batch(
    batch_count: int,
    timings: list[float],
    openfhe_reference_us: float,
    single_fpga_reference_us: float,
) -> dict[str, float | int]:
    median_batch_us = statistics.median(timings)
    mean_batch_us = statistics.fmean(timings)
    p95_batch_us = percentile_nearest_rank(timings, 0.95)

    core_plus_drain_cycles = batch_count * (
        PER_PRODUCT_CORE_CYCLES + WRITE_DRAIN_CYCLES_PER_PRODUCT
    )
    core_plus_drain_us = core_plus_drain_cycles / CLOCK_MHZ
    overhead_batch_us = median_batch_us - core_plus_drain_us
    median_product_us = median_batch_us / batch_count
    mean_product_us = mean_batch_us / batch_count
    p95_product_us = p95_batch_us / batch_count
    overhead_product_us = overhead_batch_us / batch_count

    input_words = 2 + batch_count * WORDS_PER_PRODUCT_INPUT
    output_words = batch_count * WORDS_PER_PRODUCT_OUTPUT

    return {
        "batch_count": batch_count,
        "input_words": input_words,
        "input_bytes": 8 * input_words,
        "output_words": output_words,
        "output_bytes": 8 * output_words,
        "minimum_batch_us": min(timings),
        "median_batch_us": median_batch_us,
        "mean_batch_us": mean_batch_us,
        "p95_batch_us": p95_batch_us,
        "maximum_batch_us": max(timings),
        "median_product_us": median_product_us,
        "mean_product_us": mean_product_us,
        "p95_product_us": p95_product_us,
        "core_plus_drain_cycles": core_plus_drain_cycles,
        "core_plus_drain_us": core_plus_drain_us,
        "median_batch_overhead_us": overhead_batch_us,
        "amortized_overhead_us": overhead_product_us,
        "products_per_second": 1_000_000.0 / median_product_us,
        "individual_towers_per_second": 2_000_000.0 / median_product_us,
        "speedup_vs_openfhe": openfhe_reference_us / median_product_us,
        "speedup_vs_single_fpga": single_fpga_reference_us / median_product_us,
    }


def print_summary(
    summary: dict[str, float | int],
    openfhe_reference_us: float,
) -> None:
    batch_count = int(summary["batch_count"])
    print("\n============================================================")
    print(f"BATCH COUNT {batch_count}")
    print("============================================================")
    print(f"Input:  {summary['input_words']} words, {summary['input_bytes']} bytes")
    print(f"Output: {summary['output_words']} words, {summary['output_bytes']} bytes")
    print(f"Minimum batch: {summary['minimum_batch_us']:.2f} us")
    print(f"Median batch: {summary['median_batch_us']:.2f} us")
    print(f"Mean batch: {summary['mean_batch_us']:.2f} us")
    print(f"p95 batch: {summary['p95_batch_us']:.2f} us")
    print(f"Maximum batch: {summary['maximum_batch_us']:.2f} us")
    print(f"Median per DCRTPoly product: {summary['median_product_us']:.2f} us")
    print(f"Mean per DCRTPoly product: {summary['mean_product_us']:.2f} us")
    print(f"p95 per DCRTPoly product: {summary['p95_product_us']:.2f} us")
    print(
        f"Median batch DMA/software overhead: "
        f"{summary['median_batch_overhead_us']:.2f} us"
    )
    print(
        f"Amortized overhead per product: "
        f"{summary['amortized_overhead_us']:.2f} us"
    )
    print(f"Measured DCRTPoly products/s: {summary['products_per_second']:.2f}")
    print(
        f"Speedup versus single-product FPGA: "
        f"{summary['speedup_vs_single_fpga']:.3f}x"
    )

    if float(summary["median_product_us"]) < openfhe_reference_us:
        print(
            f"PASS: amortized FPGA median is "
            f"{summary['speedup_vs_openfhe']:.3f}x faster than OpenFHE"
        )
    else:
        print(
            f"INFO: amortized FPGA median is "
            f"{1.0 / float(summary['speedup_vs_openfhe']):.3f}x "
            "slower than OpenFHE"
        )


def write_csv(path: Path, summaries: list[dict[str, float | int]]) -> None:
    fieldnames = list(summaries[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summaries)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Sweep batch counts using the existing timing-clean PYNQ-Z2 "
            "batched two-tower OpenFHE overlay."
        )
    )
    parser.add_argument("--overlay", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--batch-counts",
        type=int,
        nargs="+",
        default=list(DEFAULT_BATCH_COUNTS),
    )
    parser.add_argument("--timed-batches", type=int, default=20)
    parser.add_argument(
        "--openfhe-reference-us",
        type=float,
        default=DEFAULT_OPENFHE_REFERENCE_US,
    )
    parser.add_argument(
        "--single-fpga-reference-us",
        type=float,
        default=DEFAULT_SINGLE_FPGA_REFERENCE_US,
    )
    args = parser.parse_args()

    batch_counts = list(dict.fromkeys(args.batch_counts))
    if not batch_counts:
        raise ValueError("At least one batch count is required")
    if any(count <= 0 for count in batch_counts):
        raise ValueError("Batch counts must be positive")
    if args.timed_batches <= 0:
        raise ValueError("--timed-batches must be positive")

    maximum_batch_count = max(batch_counts)
    vector_root = args.vectors.resolve()
    output_root = args.output.resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    products = load_products(vector_root, maximum_batch_count)
    profile_frame = build_profile_frame(vector_root)

    overlay = Overlay(str(args.overlay.resolve()), download=True)
    dma = resolve_dma(overlay)

    profile_buffer = allocate(shape=(PROFILE_WORDS,), dtype=np.uint64)
    profile_buffer[:] = profile_frame
    try:
        profile_us = send_only(dma, profile_buffer)
    finally:
        profile_buffer.freebuffer()

    time.sleep(0.001)
    print("PASS: q0 and q1 profiles loaded once for the complete batch sweep")
    print(f"Profile frame: {PROFILE_BYTES} bytes")
    print(f"Profile load: {profile_us:.2f} us")

    summaries: list[dict[str, float | int]] = []

    for batch_count in batch_counts:
        batch_frame, expected = build_batch_frame(products, batch_count)
        input_words = batch_frame.size
        output_words = batch_count * WORDS_PER_PRODUCT_OUTPUT

        send_buffer = allocate(shape=(input_words,), dtype=np.uint64)
        receive_buffer = allocate(shape=(output_words,), dtype=np.uint64)

        try:
            send_buffer[:] = batch_frame

            first_us = run_batch(dma, send_buffer, receive_buffer)
            final0, final1 = validate_batch(
                receive_buffer,
                expected,
                f"Batch {batch_count} first run",
            )

            print(f"\nPASS: batch count {batch_count} first run exactly matches OpenFHE")
            print(f"First batch: {first_us:.2f} us")
            print(f"First amortized product: {first_us / batch_count:.2f} us")

            timings: list[float] = []
            for run_index in range(args.timed_batches):
                elapsed_us = run_batch(dma, send_buffer, receive_buffer)
                final0, final1 = validate_batch(
                    receive_buffer,
                    expected,
                    f"Batch {batch_count} timed run {run_index}",
                )
                timings.append(elapsed_us)

            batch_output = output_root / f"batch{batch_count}"
            batch_output.mkdir(parents=True, exist_ok=True)

            for product_index in range(batch_count):
                start = product_index * WORDS_PER_PRODUCT_OUTPUT
                stop = start + WORDS_PER_PRODUCT_OUTPUT
                np.asarray(final0[start:stop], dtype="<u4").tofile(
                    batch_output / f"fpga_product{product_index}_tower0.bin"
                )
                np.asarray(final1[start:stop], dtype="<u4").tofile(
                    batch_output / f"fpga_product{product_index}_tower1.bin"
                )

            summary = summarize_batch(
                batch_count=batch_count,
                timings=timings,
                openfhe_reference_us=args.openfhe_reference_us,
                single_fpga_reference_us=args.single_fpga_reference_us,
            )
            summaries.append(summary)

            print(
                f"PASS: {args.timed_batches} timed batches of count "
                f"{batch_count} all match OpenFHE"
            )
            print_summary(summary, args.openfhe_reference_us)

        finally:
            send_buffer.freebuffer()
            receive_buffer.freebuffer()

    csv_path = output_root / "batch_sweep.csv"
    json_path = output_root / "batch_sweep.json"
    write_csv(csv_path, summaries)
    json_path.write_text(
        json.dumps(
            {
                "profile_load_us": profile_us,
                "timed_batches_per_count": args.timed_batches,
                "openfhe_reference_us": args.openfhe_reference_us,
                "single_fpga_reference_us": args.single_fpga_reference_us,
                "summaries": summaries,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    counts = np.asarray(
        [int(summary["batch_count"]) for summary in summaries],
        dtype=np.float64,
    )
    medians = np.asarray(
        [float(summary["median_batch_us"]) for summary in summaries],
        dtype=np.float64,
    )
    design = np.column_stack([np.ones_like(counts), counts])
    fixed_us, incremental_us = np.linalg.lstsq(design, medians, rcond=None)[0]

    per_product = [float(summary["median_product_us"]) for summary in summaries]
    monotonic = all(
        current <= previous
        for previous, current in zip(per_product, per_product[1:])
    )
    best_index = int(np.argmin(per_product))
    best = summaries[best_index]

    print("\n============================================================")
    print("BATCH SWEEP COMPLETE")
    print("============================================================")
    print(f"Linear fit fixed batch cost: {fixed_us:.2f} us")
    print(f"Linear fit incremental cost/product: {incremental_us:.2f} us")
    print(f"Linear-fit asymptotic products/s: {1_000_000.0 / incremental_us:.2f}")
    print(f"Best measured batch count: {best['batch_count']}")
    print(f"Best measured median/product: {best['median_product_us']:.2f} us")
    print(f"Best measured OpenFHE speedup: {best['speedup_vs_openfhe']:.3f}x")

    if monotonic:
        print("PASS: amortized median did not increase as batch count grew")
    else:
        print("INFO: amortized medians contain a non-monotonic step; inspect the CSV")

    print(f"CSV:  {csv_path}")
    print(f"JSON: {json_path}")
    print("PASS board arbitrary-batch OpenFHE sweep")


if __name__ == "__main__":
    main()
