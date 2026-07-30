#!/usr/bin/env python3

from pathlib import Path
from time import monotonic, perf_counter_ns

from pynq import MMIO, Overlay


BITSTREAM = Path("/home/xilinx/pynq_poly_mul256.bit")

INPUT_A_FILE = Path("/home/xilinx/n256_input_a.mem")
INPUT_B_FILE = Path("/home/xilinx/n256_input_b.mem")
EXPECTED_FILE = Path("/home/xilinx/n256_convolution.mem")

EXPECTED_BASE = 0x43C30000
EXPECTED_RANGE = 0x00010000

REG_CONTROL = 0x0000
REG_STATUS = 0x0004
REG_CYCLES = 0x0008
REG_VERSION = 0x000C
REG_MODULUS = 0x0010
REG_N = 0x0014
REG_MULTS = 0x0018

A_BASE = 0x0100
B_BASE = 0x0500
RESULT_BASE = 0x0900

EXPECTED_VERSION = 0x00020000
EXPECTED_MODULUS = 1073692673
EXPECTED_N = 256
EXPECTED_MULTS = 4096
EXPECTED_CYCLES = 159249

CLOCK_HZ = 100_000_000


def read_mem_file(path: Path, expected_length: int) -> list[int]:
    values: list[int] = []

    for raw_line in path.read_text(encoding="ascii").splitlines():
        line = raw_line.split("//", 1)[0].strip()

        if line:
            values.append(int(line, 16))

    if len(values) != expected_length:
        raise RuntimeError(
            f"{path} contains {len(values)} values; "
            f"expected {expected_length}"
        )

    return values


def require_equal(name: str, actual: int, expected: int) -> None:
    if actual != expected:
        raise RuntimeError(
            f"{name}: got 0x{actual:08x} ({actual}), "
            f"expected 0x{expected:08x} ({expected})"
        )


def run_product(mmio: MMIO) -> tuple[int, int, list[int]]:
    # Clear any completion state left from a prior operation.
    mmio.write(REG_CONTROL, 0x2)

    cleared_status = int(mmio.read(REG_STATUS))

    if cleared_status & 0x2:
        raise RuntimeError(
            f"Sticky completion did not clear: "
            f"STATUS=0x{cleared_status:08x}"
        )

    start_ns = perf_counter_ns()

    mmio.write(REG_CONTROL, 0x1)

    deadline = monotonic() + 10.0
    observed_busy = False
    last_status = 0

    while monotonic() < deadline:
        last_status = int(mmio.read(REG_STATUS))

        if last_status & 0x1:
            observed_busy = True

        if last_status & 0x2:
            break
    else:
        raise TimeoutError(
            f"N=256 FPGA operation timed out; "
            f"STATUS=0x{last_status:08x}"
        )

    elapsed_ns = perf_counter_ns() - start_ns

    status = int(mmio.read(REG_STATUS))
    cycles = int(mmio.read(REG_CYCLES))

    if not observed_busy:
        raise RuntimeError("Busy was never observed")

    if status & 0x1:
        raise RuntimeError(
            f"Busy remained asserted after completion: "
            f"STATUS=0x{status:08x}"
        )

    result = [
        int(mmio.read(RESULT_BASE + 4 * index))
        for index in range(EXPECTED_N)
    ]

    return cycles, elapsed_ns, result


def verify_result(
    actual: list[int],
    expected: list[int],
    label: str,
) -> None:
    mismatches = [
        (index, actual_value, expected_value)
        for index, (actual_value, expected_value) in enumerate(
            zip(actual, expected)
        )
        if actual_value != expected_value
    ]

    if mismatches:
        print(f"\nFAIL: {label}")

        for index, actual_value, expected_value in mismatches[:20]:
            print(
                f"  C[{index:3d}] "
                f"actual={actual_value:10d} "
                f"expected={expected_value:10d}"
            )

        if len(mismatches) > 20:
            print(
                f"  ... plus {len(mismatches) - 20} more mismatches"
            )

        raise RuntimeError(
            f"{len(mismatches)} coefficients were incorrect"
        )


def main() -> None:
    input_a = read_mem_file(INPUT_A_FILE, EXPECTED_N)
    input_b = read_mem_file(INPUT_B_FILE, EXPECTED_N)
    expected = read_mem_file(EXPECTED_FILE, EXPECTED_N)

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

    if "poly_mul256_0" not in overlay.ip_dict:
        raise RuntimeError(
            "poly_mul256_0 was not found in the HWH metadata"
        )

    description = overlay.ip_dict["poly_mul256_0"]

    base_address = int(description["phys_addr"])
    address_range = int(description["addr_range"])

    require_equal(
        "poly_mul256 base",
        base_address,
        EXPECTED_BASE,
    )

    if address_range < EXPECTED_RANGE:
        raise RuntimeError(
            f"Address range is 0x{address_range:x}; "
            f"expected at least 0x{EXPECTED_RANGE:x}"
        )

    mmio = MMIO(base_address, EXPECTED_RANGE)

    version = int(mmio.read(REG_VERSION))
    modulus = int(mmio.read(REG_MODULUS))
    polynomial_length = int(mmio.read(REG_N))
    multiplication_count = int(mmio.read(REG_MULTS))

    require_equal("VERSION", version, EXPECTED_VERSION)
    require_equal("MODULUS", modulus, EXPECTED_MODULUS)
    require_equal("N", polynomial_length, EXPECTED_N)
    require_equal("MULTS", multiplication_count, EXPECTED_MULTS)

    print("\nPASS: identification registers")
    print(f"  VERSION = 0x{version:08x}")
    print(f"  MODULUS = {modulus}")
    print(f"  N       = {polynomial_length}")
    print(f"  MULTS   = {multiplication_count}")

    load_start_ns = perf_counter_ns()

    for index, value in enumerate(input_a):
        mmio.write(A_BASE + 4 * index, value)

    for index, value in enumerate(input_b):
        mmio.write(B_BASE + 4 * index, value)

    load_elapsed_ns = perf_counter_ns() - load_start_ns

    print("\nPASS: loaded 512 coefficients")
    print(
        f"Python/MMIO load time: "
        f"{load_elapsed_ns / 1_000.0:.2f} us"
    )

    cycles_1, elapsed_1_ns, result_1 = run_product(mmio)

    require_equal(
        "First hardware cycle count",
        cycles_1,
        EXPECTED_CYCLES,
    )

    verify_result(
        result_1,
        expected,
        "first physical FPGA product",
    )

    print("\nPASS: first physical FPGA product matches golden convolution")
    print(f"  Hardware cycles:     {cycles_1}")
    print(
        f"  Core latency:        "
        f"{cycles_1 / (CLOCK_HZ / 1_000_000):.2f} us"
    )
    print(
        f"  Python/MMIO elapsed: "
        f"{elapsed_1_ns / 1_000.0:.2f} us"
    )

    cycles_2, elapsed_2_ns, result_2 = run_product(mmio)

    require_equal(
        "Second hardware cycle count",
        cycles_2,
        EXPECTED_CYCLES,
    )

    verify_result(
        result_2,
        expected,
        "repeated physical FPGA product",
    )

    if cycles_1 != cycles_2:
        raise RuntimeError(
            f"Cycle count changed: first={cycles_1}, second={cycles_2}"
        )

    print("\nPASS: repeated operation is constant-time and correct")
    print(f"  Repeat hardware cycles: {cycles_2}")
    print(
        f"  Repeat MMIO elapsed:    "
        f"{elapsed_2_ns / 1_000.0:.2f} us"
    )

    products_per_second = CLOCK_HZ / cycles_1

    effective_modmuls_per_second = (
        EXPECTED_MULTS * products_per_second
    )

    print("\nPhysical kernel performance:")
    print(
        f"  Polynomial products/s: "
        f"{products_per_second:.2f}"
    )
    print(
        f"  Effective modular multiplications/s: "
        f"{effective_modmuls_per_second:,.0f}"
    )

    print("\nSelected result coefficients:")

    selected_indices = [
        0, 1, 2, 3,
        63, 64, 127, 128,
        191, 192, 252, 253, 254, 255,
    ]

    for index in selected_indices:
        print(f"  C[{index:3d}] = {result_1[index]}")

    mmio.write(REG_CONTROL, 0x2)

    final_status = int(mmio.read(REG_STATUS))

    if final_status & 0x2:
        raise RuntimeError(
            "Sticky completion remained asserted after final clear"
        )

    print("\nPASS: sticky completion cleared")
    print("PASS: PYNQ-Z2 N=256 polynomial multiplier verified end to end")


if __name__ == "__main__":
    main()
