#!/usr/bin/env python3

from pathlib import Path
from statistics import mean, median
from time import perf_counter_ns

import numpy as np
from pynq import Overlay, allocate


BITSTREAM = Path(
    "/home/xilinx/pynq_poly_mul256_dma_batch32.bit"
)

INPUT_A_FILE = Path("/home/xilinx/n256_input_a.mem")
INPUT_B_FILE = Path("/home/xilinx/n256_input_b.mem")
EXPECTED_FILE = Path("/home/xilinx/n256_convolution.mem")

N = 256
BATCH_PRODUCTS = 32

INPUT_WORDS_PER_PRODUCT = 512
OUTPUT_WORDS_PER_PRODUCT = 256

BATCH_INPUT_WORDS = (
    BATCH_PRODUCTS * INPUT_WORDS_PER_PRODUCT
)

BATCH_OUTPUT_WORDS = (
    BATCH_PRODUCTS * OUTPUT_WORDS_PER_PRODUCT
)

BATCH_INPUT_BYTES = BATCH_INPUT_WORDS * 4
BATCH_OUTPUT_BYTES = BATCH_OUTPUT_WORDS * 4

CORE_CYCLES_PER_PRODUCT = 159249
CLOCK_HZ = 100_000_000

WARMUP_BATCHES = 2
TIMED_BATCHES = 20


def read_mem_file(
    path: Path,
    expected_length: int,
) -> np.ndarray:
    values: list[int] = []

    for raw_line in path.read_text(
        encoding="ascii"
    ).splitlines():
        line = raw_line.split("//", 1)[0].strip()

        if line:
            values.append(int(line, 16))

    if len(values) != expected_length:
        raise RuntimeError(
            f"{path} contains {len(values)} words; "
            f"expected {expected_length}"
        )

    return np.asarray(
        values,
        dtype=np.uint32,
    )


def percentile(
    values: list[float],
    fraction: float,
) -> float:
    ordered = sorted(values)

    index = round(
        (len(ordered) - 1) * fraction
    )

    return ordered[index]


def verify_batch(
    output_buffer,
    expected: np.ndarray,
    label: str,
) -> None:
    output = np.asarray(output_buffer).reshape(
        BATCH_PRODUCTS,
        OUTPUT_WORDS_PER_PRODUCT,
    )

    expected_batch = np.broadcast_to(
        expected,
        output.shape,
    )

    mismatch_locations = np.argwhere(
        output != expected_batch
    )

    if mismatch_locations.size == 0:
        return

    print(f"\nFAIL: {label}")

    for product, coefficient in mismatch_locations[:20]:
        product_index = int(product)
        coefficient_index = int(coefficient)

        actual_value = int(
            output[
                product_index,
                coefficient_index,
            ]
        )

        expected_value = int(
            expected[coefficient_index]
        )

        print(
            f"  product={product_index:2d} "
            f"C[{coefficient_index:3d}] "
            f"actual={actual_value:10d} "
            f"expected={expected_value:10d}"
        )

    mismatch_count = len(mismatch_locations)

    if mismatch_count > 20:
        print(
            f"  ... plus "
            f"{mismatch_count - 20} more mismatches"
        )

    raise RuntimeError(
        f"{mismatch_count} coefficients were incorrect"
    )


def run_batch(
    dma,
    input_buffer,
    output_buffer,
) -> int:
    output_buffer[:] = 0

    input_buffer.flush()
    output_buffer.flush()

    start_ns = perf_counter_ns()

    # Arm S2MM first. The accelerator's output can then never be
    # blocked waiting for the receive channel to be configured.
    dma.recvchannel.transfer(output_buffer)
    dma.sendchannel.transfer(input_buffer)

    dma.sendchannel.wait()
    dma.recvchannel.wait()

    elapsed_ns = perf_counter_ns() - start_ns

    output_buffer.invalidate()

    return elapsed_ns


def main() -> None:
    input_a = read_mem_file(
        INPUT_A_FILE,
        N,
    )

    input_b = read_mem_file(
        INPUT_B_FILE,
        N,
    )

    expected = read_mem_file(
        EXPECTED_FILE,
        N,
    )

    print(f"Loading overlay: {BITSTREAM}")

    overlay = Overlay(
        str(BITSTREAM),
        download=True,
    )

    print("\nOverlay IP blocks:")

    for name, description in sorted(
        overlay.ip_dict.items()
    ):
        print(
            f"  {name}: "
            f"type={description.get('type')} "
            f"address={description.get('phys_addr')} "
            f"range={description.get('addr_range')}"
        )

    if "axi_dma_0" not in overlay.ip_dict:
        raise RuntimeError(
            "axi_dma_0 was not found in HWH metadata"
        )

    dma = overlay.axi_dma_0

    input_buffer = allocate(
        shape=(BATCH_INPUT_WORDS,),
        dtype=np.uint32,
    )

    output_buffer = allocate(
        shape=(BATCH_OUTPUT_WORDS,),
        dtype=np.uint32,
    )

    try:
        # Input packet layout:
        #
        #   A0, B0, A1, B1, ... A31, B31
        for product in range(BATCH_PRODUCTS):
            base = (
                product
                * INPUT_WORDS_PER_PRODUCT
            )

            input_buffer[
                base : base + N
            ] = input_a

            input_buffer[
                base + N : base + 2 * N
            ] = input_b

        input_buffer.flush()

        print("\nDMA buffers:")
        print(
            f"  Input:  "
            f"physical="
            f"0x{input_buffer.physical_address:08x} "
            f"bytes={input_buffer.nbytes}"
        )

        print(
            f"  Output: "
            f"physical="
            f"0x{output_buffer.physical_address:08x} "
            f"bytes={output_buffer.nbytes}"
        )

        if input_buffer.nbytes != BATCH_INPUT_BYTES:
            raise RuntimeError(
                f"Input buffer is "
                f"{input_buffer.nbytes} bytes; "
                f"expected {BATCH_INPUT_BYTES}"
            )

        if output_buffer.nbytes != BATCH_OUTPUT_BYTES:
            raise RuntimeError(
                f"Output buffer is "
                f"{output_buffer.nbytes} bytes; "
                f"expected {BATCH_OUTPUT_BYTES}"
            )

        first_elapsed_ns = run_batch(
            dma,
            input_buffer,
            output_buffer,
        )

        verify_batch(
            output_buffer,
            expected,
            "first physical batch",
        )

        first_us = first_elapsed_ns / 1_000.0

        print(
            "\nPASS: first 32-product DMA batch "
            "matches the golden convolution"
        )

        print(
            f"  Batch elapsed:      "
            f"{first_us:.2f} us"
        )

        print(
            f"  Per product:        "
            f"{first_us / BATCH_PRODUCTS:.2f} us"
        )

        print(
            f"  Batch products/s:   "
            f"{BATCH_PRODUCTS * 1_000_000.0 / first_us:.2f}"
        )

        for warmup in range(WARMUP_BATCHES):
            elapsed_ns = run_batch(
                dma,
                input_buffer,
                output_buffer,
            )

            verify_batch(
                output_buffer,
                expected,
                f"warmup batch {warmup}",
            )

        samples_us: list[float] = []

        for batch_number in range(TIMED_BATCHES):
            elapsed_ns = run_batch(
                dma,
                input_buffer,
                output_buffer,
            )

            verify_batch(
                output_buffer,
                expected,
                f"timed batch {batch_number}",
            )

            samples_us.append(
                elapsed_ns / 1_000.0
            )

        minimum_us = min(samples_us)
        median_us = median(samples_us)
        average_us = mean(samples_us)
        p95_us = percentile(
            samples_us,
            0.95,
        )
        maximum_us = max(samples_us)

        median_per_product_us = (
            median_us / BATCH_PRODUCTS
        )

        median_products_per_second = (
            BATCH_PRODUCTS
            * 1_000_000.0
            / median_us
        )

        core_only_batch_us = (
            BATCH_PRODUCTS
            * CORE_CYCLES_PER_PRODUCT
            / (CLOCK_HZ / 1_000_000)
        )

        overhead_per_batch_us = (
            median_us
            - core_only_batch_us
        )

        overhead_per_product_us = (
            overhead_per_batch_us
            / BATCH_PRODUCTS
        )

        print(
            f"\nPASS: {TIMED_BATCHES} timed batches "
            f"({TIMED_BATCHES * BATCH_PRODUCTS} products) "
            "all match"
        )

        print(
            "\nPhysical batch-32 DMA performance:"
        )

        print(
            f"  Minimum batch:       "
            f"{minimum_us:.2f} us"
        )

        print(
            f"  Median batch:        "
            f"{median_us:.2f} us"
        )

        print(
            f"  Mean batch:          "
            f"{average_us:.2f} us"
        )

        print(
            f"  95th percentile:     "
            f"{p95_us:.2f} us"
        )

        print(
            f"  Maximum batch:       "
            f"{maximum_us:.2f} us"
        )

        print(
            f"  Median per product:  "
            f"{median_per_product_us:.2f} us"
        )

        print(
            f"  Median products/s:   "
            f"{median_products_per_second:.2f}"
        )

        print(
            f"  Sum of core latency: "
            f"{core_only_batch_us:.2f} us"
        )

        print(
            f"  Batch overhead:      "
            f"{overhead_per_batch_us:.2f} us"
        )

        print(
            f"  Overhead/product:    "
            f"{overhead_per_product_us:.2f} us"
        )

        print("\nTransfer sizes:")

        print(
            f"  MM2S input:  "
            f"{BATCH_INPUT_BYTES} bytes"
        )

        print(
            f"  S2MM output: "
            f"{BATCH_OUTPUT_BYTES} bytes"
        )

        output = np.asarray(
            output_buffer
        ).reshape(
            BATCH_PRODUCTS,
            OUTPUT_WORDS_PER_PRODUCT,
        )

        print(
            "\nSelected result coefficients:"
        )

        for product in (0, 31):
            for coefficient in (
                0,
                1,
                127,
                128,
                254,
                255,
            ):
                print(
                    f"  product {product:2d} "
                    f"C[{coefficient:3d}] = "
                    f"{int(output[product, coefficient])}"
                )

        print(
            "\nPASS: PYNQ-Z2 batch-32 DMA "
            "polynomial multiplier verified end to end"
        )

    finally:
        input_buffer.freebuffer()
        output_buffer.freebuffer()


if __name__ == "__main__":
    main()
