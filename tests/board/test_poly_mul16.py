#!/usr/bin/env python3

from pathlib import Path
from time import monotonic, perf_counter_ns

from pynq import MMIO, Overlay


BITSTREAM = Path("/home/xilinx/pynq_poly_mul16.bit")

INPUT_A_FILE = Path("/home/xilinx/input_a.mem")
INPUT_B_FILE = Path("/home/xilinx/input_b.mem")
EXPECTED_FILE = Path("/home/xilinx/convolution.mem")

EXPECTED_BASE = 0x43C20000
EXPECTED_RANGE = 0x00010000

REG_CONTROL = 0x00
REG_STATUS = 0x04
REG_CYCLES = 0x08
REG_VERSION = 0x0C
REG_MODULUS = 0x10
REG_N = 0x14
REG_MULTS = 0x18

A_BASE = 0x20
B_BASE = 0x60
RESULT_BASE = 0xA0

EXPECTED_VERSION = 0x00010000
EXPECTED_MODULUS = 1073692673
EXPECTED_N = 16
EXPECTED_MULTS = 112


def read_mem_file(path: Path) -> list[int]:
    values: list[int] = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("//", 1)[0].strip()

        if not line:
            continue

        values.append(int(line, 16))

    if len(values) != 16:
        raise RuntimeError(
            f"{path} contains {len(values)} values; expected 16"
        )

    return values


def require_equal(name: str, actual: int, expected: int) -> None:
    if actual != expected:
        raise RuntimeError(
            f"{name}: got 0x{actual:08x} ({actual}), "
            f"expected 0x{expected:08x} ({expected})"
        )


def main() -> None:
    input_a = read_mem_file(INPUT_A_FILE)
    input_b = read_mem_file(INPUT_B_FILE)
    expected = read_mem_file(EXPECTED_FILE)

    print(f"Loading overlay: {BITSTREAM}")

    overlay = Overlay(str(BITSTREAM), download=True)

    print("\nOverlay IP blocks:")

    for name, description in sorted(overlay.ip_dict.items()):
        address = description.get("phys_addr")
        span = description.get("addr_range")
        ip_type = description.get("type")

        print(
            f"  {name}: type={ip_type} "
            f"address={address!r} range={span!r}"
        )

    if "poly_mul16_0" not in overlay.ip_dict:
        raise RuntimeError(
            "poly_mul16_0 was not found in the HWH metadata"
        )

    description = overlay.ip_dict["poly_mul16_0"]

    base_address = int(description["phys_addr"])
    address_range = int(description["addr_range"])

    require_equal(
        "poly_mul16 base address",
        base_address,
        EXPECTED_BASE,
    )

    if address_range < EXPECTED_RANGE:
        raise RuntimeError(
            f"Address range is only 0x{address_range:x}; "
            f"expected at least 0x{EXPECTED_RANGE:x}"
        )

    mmio = MMIO(base_address, EXPECTED_RANGE)

    version = int(mmio.read(REG_VERSION))
    modulus = int(mmio.read(REG_MODULUS))
    polynomial_length = int(mmio.read(REG_N))
    modular_multiplications = int(mmio.read(REG_MULTS))

    require_equal(
        "VERSION",
        version,
        EXPECTED_VERSION,
    )

    require_equal(
        "MODULUS",
        modulus,
        EXPECTED_MODULUS,
    )

    require_equal(
        "N",
        polynomial_length,
        EXPECTED_N,
    )

    require_equal(
        "MULTS",
        modular_multiplications,
        EXPECTED_MULTS,
    )

    print("\nPASS: identification registers")
    print(f"  VERSION = 0x{version:08x}")
    print(f"  MODULUS = {modulus}")
    print(f"  N       = {polynomial_length}")
    print(f"  MULTS   = {modular_multiplications}")

    for index, value in enumerate(input_a):
        mmio.write(A_BASE + 4 * index, value)

    for index, value in enumerate(input_b):
        mmio.write(B_BASE + 4 * index, value)

    for index, expected_value in enumerate(input_a):
        actual = int(mmio.read(A_BASE + 4 * index))
        require_equal(f"A[{index}] readback", actual, expected_value)

    for index, expected_value in enumerate(input_b):
        actual = int(mmio.read(B_BASE + 4 * index))
        require_equal(f"B[{index}] readback", actual, expected_value)

    print("PASS: loaded and read back both input polynomials")

    # Clear any sticky completion state left from an earlier run.
    mmio.write(REG_CONTROL, 0x2)

    wall_start_ns = perf_counter_ns()

    # Start the complete forward/pointwise/inverse pipeline.
    mmio.write(REG_CONTROL, 0x1)

    deadline = monotonic() + 5.0
    last_status = 0

    while monotonic() < deadline:
        last_status = int(mmio.read(REG_STATUS))

        if last_status & 0x2:
            break
    else:
        raise TimeoutError(
            f"FPGA operation timed out; STATUS=0x{last_status:08x}"
        )

    wall_elapsed_ns = perf_counter_ns() - wall_start_ns

    status = int(mmio.read(REG_STATUS))
    cycles = int(mmio.read(REG_CYCLES))

    if status & 0x1:
        raise RuntimeError(
            f"Busy remained asserted after completion: "
            f"STATUS=0x{status:08x}"
        )

    actual_result = [
        int(mmio.read(RESULT_BASE + 4 * index))
        for index in range(16)
    ]

    mismatches = []

    for index, (actual, expected_value) in enumerate(
        zip(actual_result, expected)
    ):
        if actual != expected_value:
            mismatches.append(
                (index, actual, expected_value)
            )

    if mismatches:
        print("\nFAIL: result mismatches")

        for index, actual, expected_value in mismatches:
            print(
                f"  coefficient {index:2d}: "
                f"actual={actual:10d} "
                f"expected={expected_value:10d}"
            )

        raise RuntimeError(
            f"{len(mismatches)} result coefficients were incorrect"
        )

    print("\nPASS: physical FPGA result matches golden convolution")
    print(f"STATUS:             0x{status:08x}")
    print(f"Hardware cycles:    {cycles}")
    print(f"At 100 MHz:         {cycles / 100.0:.2f} us")
    print(f"Python/MMIO elapsed:{wall_elapsed_ns / 1_000.0:9.2f} us")

    print("\nResult coefficients:")

    for index, value in enumerate(actual_result):
        print(f"  C[{index:2d}] = {value}")

    # Verify that the sticky done flag can be cleared.
    mmio.write(REG_CONTROL, 0x2)

    cleared_status = int(mmio.read(REG_STATUS))

    if cleared_status & 0x2:
        raise RuntimeError(
            "Sticky completion flag did not clear"
        )

    print("\nPASS: sticky completion cleared")
    print("PASS: PYNQ-Z2 poly_mul16 hardware verified end to end")


if __name__ == "__main__":
    main()
