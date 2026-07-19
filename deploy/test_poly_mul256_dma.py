#!/usr/bin/env python3

from pathlib import Path
from statistics import mean, median
from time import perf_counter_ns

import numpy as np
from pynq import Overlay, allocate


BITSTREAM = Path("/home/xilinx/pynq_poly_mul256_dma.bit")

INPUT_A_FILE = Path("/home/xilinx/n256_input_a.mem")
INPUT_B_FILE = Path("/home/xilinx/n256_input_b.mem")
EXPECTED_FILE = Path("/home/xilinx/n256_convolution.mem")

N = 256
INPUT_WORDS = 512
OUTPUT_WORDS = 256

INPUT_BYTES = INPUT_WORDS * 4
OUTPUT_BYTES = OUTPUT_WORDS * 4

CORE_CYCLES = 159249
CLOCK_HZ = 100_000_000

WARMUP_RUNS = 3
TIMED_RUNS = 100


def read_mem_file(path: Path, expected_length: int) -> np.ndarray:
    values: list[int] = []

    for raw_line in path.read_text(encoding="ascii").splitlines():
        line = raw_line.split("//", 1)[0].strip()

        if line:
            values.append(int(line, 16))

    if len(values) != expected_length:
        raise RuntimeError(
            f"{path} contains {len(values)} words; "
            f"expected {expected_length}"
        )

    return np.asarray(values, dtype=np.uint32)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)

    index = round((len(ordered) - 1) * fraction)

    return ordered[index]


def verify_result(
    actual: np.ndarray,
    expected: np.ndarray,
    label: str,
) -> None:
    mismatches = np.flatnonzero(actual != expected)

    if mismatches.size == 0:
        return

    print(f"\nFAIL: {label}")

    for raw_index in mismatches[:20]:
        index = int(raw_index)

        print(
            f"  C[{index:3d}] "
            f"actual={int(actual[index]):10d} "
            f"expected={int(expected[index]):10d}"
        )

    if mismatches.size > 20:
        print(f"  ... plus {mismatches.size - 20} more mismatches")

    raise RuntimeError(
        f"{mismatches.size} result coefficients were incorrect"
    )


def run_dma_product(
    dma,
    input_buffer,
    output_buffer,
) -> int:
    output_buffer[:] = 0

    input_buffer.flush()
    output_buffer.flush()

    start_ns = perf_counter_ns()

    # Arm the receive channel first so the accelerator can never block
    # while trying to return its first result word.
    dma.recvchannel.transfer(output_buffer)
    dma.sendchannel.transfer(input_buffer)

    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_ns = perf_counter_ns() - start_ns

    output_buffer.invalidate()

    return elapsed_ns


def main() -> None:
    input_a = read_mem_file(INPUT_A_FILE, N)
    input_b = read_mem_file(INPUT_B_FILE, N)
    expected = read_mem_file(EXPECTED_FILE, N)

    print(f"Loading overlay: {BITSTREAM}")

    overlay = Overlay(str(BITSTREAM), download=True)

    print("\nOverlay IP blocks:")

    for name, description in sorted(overlay.ip_dict.items()):
        print(
            f"  {name}: "
            f"type={description.get('type')} "
            f"address={description.get('phys_addr')} "
            f"range={description.get('addr_range')}"
        )

    if "axi_dma_0" not in overlay.ip_dict:
        raise RuntimeError("axi_dma_0 was not found in the HWH metadata")

    dma = overlay.axi_dma_0

    if not dma.sendchannel:
        raise RuntimeError("DMA MM2S/send channel is unavailable")

    if not dma.recvchannel:
        raise RuntimeError("DMA S2MM/receive channel is unavailable")

    input_buffer = allocate(
        shape=(INPUT_WORDS,),
        dtype=np.uint32,
    )

    output_buffer = allocate(
        shape=(OUTPUT_WORDS,),
        dtype=np.uint32,
    )

    try:
        input_buffer[0:N] = input_a
        input_buffer[N:2 * N] = input_b
        input_buffer.flush()

        print("\nDMA buffers:")
        print(
            f"  Input:  physical=0x{input_buffer.physical_address:08x} "
            f"bytes={input_buffer.nbytes}"
        )
        print(
            f"  Output: physical=0x{output_buffer.physical_address:08x} "
            f"bytes={output_buffer.nbytes}"
        )

        first_elapsed_ns = run_dma_product(
            dma,
            input_buffer,
            output_buffer,
        )

        verify_result(
            np.asarray(output_buffer),
            expected,
            "first physical DMA product",
        )

        print("\nPASS: first DMA product matches golden convolution")
        print(
            f"  End-to-end DMA elapsed: "
            f"{first_elapsed_ns / 1_000.0:.2f} us"
        )
        print(
            f"  Fixed FPGA core latency: "
            f"{CORE_CYCLES / (CLOCK_HZ / 1_000_000):.2f} us"
        )

        for _ in range(WARMUP_RUNS):
            run_dma_product(
                dma,
                input_buffer,
                output_buffer,
            )

            verify_result(
                np.asarray(output_buffer),
                expected,
                "DMA warmup product",
            )

        samples_us: list[float] = []

        for run_number in range(TIMED_RUNS):
            elapsed_ns = run_dma_product(
                dma,
                input_buffer,
                output_buffer,
            )

            verify_result(
                np.asarray(output_buffer),
                expected,
                f"timed DMA product {run_number}",
            )

            samples_us.append(elapsed_ns / 1_000.0)

        median_us = median(samples_us)
        mean_us = mean(samples_us)
        minimum_us = min(samples_us)
        maximum_us = max(samples_us)
        p95_us = percentile(samples_us, 0.95)

        print(
            f"\nPASS: {TIMED_RUNS} timed DMA products "
            "all match the golden convolution"
        )

        print("\nPhysical DMA round-trip performance:")
        print(f"  Minimum:            {minimum_us:.2f} us")
        print(f"  Median:             {median_us:.2f} us")
        print(f"  Mean:               {mean_us:.2f} us")
        print(f"  95th percentile:    {p95_us:.2f} us")
        print(f"  Maximum:            {maximum_us:.2f} us")
        print(f"  Median products/s:  {1_000_000.0 / median_us:.2f}")

        dma_overhead_us = (
            median_us
            - CORE_CYCLES / (CLOCK_HZ / 1_000_000)
        )

        print(
            f"  Median DMA/software overhead beyond core: "
            f"{dma_overhead_us:.2f} us"
        )

        print("\nTransfer sizes:")
        print(f"  MM2S input:  {INPUT_BYTES} bytes")
        print(f"  S2MM output: {OUTPUT_BYTES} bytes")

        print("\nSelected result coefficients:")

        for index in (
            0, 1, 2, 3,
            63, 64, 127, 128,
            191, 192, 252, 253, 254, 255,
        ):
            print(f"  C[{index:3d}] = {int(output_buffer[index])}")

        print(
            "\nPASS: PYNQ-Z2 N=256 DMA polynomial multiplier "
            "verified end to end"
        )

    finally:
        input_buffer.freebuffer()
        output_buffer.freebuffer()


if __name__ == "__main__":
    main()
