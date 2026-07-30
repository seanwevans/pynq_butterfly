#!/usr/bin/env python3
"""
Generate and validate the exact OpenFHE CKKS tower-0 N=4096
negacyclic NTT profile used by the FPGA implementation.

Hardware convention
-------------------
Forward:
    1. Multiply natural-order a[j] by psi^j.
    2. Store the twisted value at bit_reverse(j).
    3. Execute an in-place radix-2 DIT cyclic NTT with omega=psi^2.
    4. Output is natural order.

Inverse:
    1. Store natural-order transform values at bit_reverse(j).
    2. Execute an in-place radix-2 DIT cyclic NTT with omega^-1.
    3. Multiply natural-order coefficient j by N^-1 * psi^-j.

Twiddle ROMs are compact and stage-major. Stage s begins at address
2^s - 1 and contains 2^s words.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import random
from pathlib import Path
from typing import Iterable, Sequence


DEFAULT_PROFILE = (
    Path(__file__).resolve().parents[1]
    / "profiles"
    / "openfhe-ckks-tower0-n4096.json"
)

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "tests"
    / "fixtures"
    / "ntt_n4096"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the N=4096 OpenFHE tower-0 FPGA golden model."
    )

    parser.add_argument(
        "--profile",
        type=Path,
        default=DEFAULT_PROFILE,
        help=f"Profile JSON path (default: {DEFAULT_PROFILE})",
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output directory (default: {DEFAULT_OUTPUT})",
    )

    parser.add_argument(
        "--roundtrip-tests",
        type=int,
        default=100,
        help="Number of dense forward/inverse round-trip tests.",
    )

    parser.add_argument(
        "--sparse-convolution-tests",
        type=int,
        default=20,
        help="Number of exact sparse schoolbook convolution tests.",
    )

    parser.add_argument(
        "--dense-evaluation-tests",
        type=int,
        default=20,
        help="Number of dense product root-evaluation checks.",
    )

    parser.add_argument(
        "--seed",
        type=lambda value: int(value, 0),
        default=0x4096C0DE,
        help="Validation PRNG seed.",
    )

    return parser.parse_args()


def load_profile(path: Path) -> dict[str, int | str]:
    try:
        profile = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"Profile does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc

    required = (
        "ring_dimension",
        "cyclotomic_order",
        "modulus",
        "source_ring_dimension",
        "source_cyclotomic_order",
        "source_root",
        "input_seed",
    )

    missing = [key for key in required if key not in profile]

    if missing:
        raise SystemExit(
            f"Profile {path} is missing required keys: {', '.join(missing)}"
        )

    return profile


def require_power_of_two(value: int, name: str) -> None:
    if value <= 0 or (value & (value - 1)) != 0:
        raise ValueError(f"{name} must be a positive power of two; got {value}")


def bit_reverse(value: int, width: int) -> int:
    reversed_value = 0

    for _ in range(width):
        reversed_value = (reversed_value << 1) | (value & 1)
        value >>= 1

    return reversed_value


def make_bit_reverse_table(n: int, log_n: int) -> list[int]:
    return [bit_reverse(index, log_n) for index in range(n)]


def powers(base: int, count: int, modulus: int) -> list[int]:
    output: list[int] = []
    value = 1

    for _ in range(count):
        output.append(value)
        value = (value * base) % modulus

    return output


def make_stage_twiddles(
    root: int,
    n: int,
    log_n: int,
    modulus: int,
) -> list[list[int]]:
    stages: list[list[int]] = []

    for stage in range(log_n):
        half = 1 << stage
        step = n // (2 * half)
        stage_root = pow(root, step, modulus)
        stages.append(powers(stage_root, half, modulus))

    return stages


def flatten_stages(stages: Sequence[Sequence[int]]) -> list[int]:
    return [value for stage in stages for value in stage]


def place_bit_reversed(
    natural_values: Sequence[int],
    bit_reverse_table: Sequence[int],
) -> list[int]:
    n = len(natural_values)
    output = [0] * n

    for index, value in enumerate(natural_values):
        output[bit_reverse_table[index]] = value

    return output


def cyclic_ntt_from_bit_reversed(
    bit_reversed_values: Sequence[int],
    stage_twiddles: Sequence[Sequence[int]],
    modulus: int,
    capture_stages: bool = False,
) -> tuple[list[int], list[list[int]]]:
    memory = list(bit_reversed_values)
    n = len(memory)
    snapshots: list[list[int]] = []

    for stage, twiddles in enumerate(stage_twiddles):
        half = 1 << stage
        span = half << 1

        if len(twiddles) != half:
            raise ValueError(
                f"Stage {stage} has {len(twiddles)} twiddles; expected {half}"
            )

        for group_base in range(0, n, span):
            for j, twiddle in enumerate(twiddles):
                left = group_base + j
                right = left + half

                u = memory[left]
                v = (memory[right] * twiddle) % modulus

                memory[left] = (u + v) % modulus
                memory[right] = (u - v) % modulus

        if capture_stages:
            snapshots.append(memory.copy())

    return memory, snapshots


def forward_negacyclic(
    coefficients: Sequence[int],
    twist_factors: Sequence[int],
    bit_reverse_table: Sequence[int],
    forward_twiddles: Sequence[Sequence[int]],
    modulus: int,
    capture_stages: bool = False,
) -> tuple[
    list[int],
    list[int],
    list[int],
    list[list[int]],
]:
    twisted = [
        (coefficient * twist) % modulus
        for coefficient, twist in zip(coefficients, twist_factors)
    ]

    bit_reversed = place_bit_reversed(
        twisted,
        bit_reverse_table,
    )

    transformed, snapshots = cyclic_ntt_from_bit_reversed(
        bit_reversed,
        forward_twiddles,
        modulus,
        capture_stages,
    )

    return transformed, twisted, bit_reversed, snapshots


def inverse_negacyclic(
    transformed: Sequence[int],
    inverse_scale_factors: Sequence[int],
    bit_reverse_table: Sequence[int],
    inverse_twiddles: Sequence[Sequence[int]],
    modulus: int,
    capture_stages: bool = False,
) -> tuple[
    list[int],
    list[int],
    list[int],
    list[list[int]],
]:
    bit_reversed = place_bit_reversed(
        transformed,
        bit_reverse_table,
    )

    cyclic_inverse, snapshots = cyclic_ntt_from_bit_reversed(
        bit_reversed,
        inverse_twiddles,
        modulus,
        capture_stages,
    )

    coefficients = [
        (value * scale) % modulus
        for value, scale in zip(
            cyclic_inverse,
            inverse_scale_factors,
        )
    ]

    return coefficients, cyclic_inverse, bit_reversed, snapshots


def polynomial_product(
    a: Sequence[int],
    b: Sequence[int],
    twist_factors: Sequence[int],
    inverse_scale_factors: Sequence[int],
    bit_reverse_table: Sequence[int],
    forward_twiddles: Sequence[Sequence[int]],
    inverse_twiddles: Sequence[Sequence[int]],
    modulus: int,
) -> list[int]:
    transformed_a, _, _, _ = forward_negacyclic(
        a,
        twist_factors,
        bit_reverse_table,
        forward_twiddles,
        modulus,
    )

    transformed_b, _, _, _ = forward_negacyclic(
        b,
        twist_factors,
        bit_reverse_table,
        forward_twiddles,
        modulus,
    )

    pointwise = [
        (left * right) % modulus
        for left, right in zip(transformed_a, transformed_b)
    ]

    product, _, _, _ = inverse_negacyclic(
        pointwise,
        inverse_scale_factors,
        bit_reverse_table,
        inverse_twiddles,
        modulus,
    )

    return product


def sparse_negacyclic_reference(
    a_entries: Sequence[tuple[int, int]],
    b_entries: Sequence[tuple[int, int]],
    n: int,
    modulus: int,
) -> list[int]:
    output = [0] * n

    for left_index, left_value in a_entries:
        for right_index, right_value in b_entries:
            raw_index = left_index + right_index
            product = (left_value * right_value) % modulus

            if raw_index < n:
                output[raw_index] = (
                    output[raw_index] + product
                ) % modulus
            else:
                output[raw_index - n] = (
                    output[raw_index - n] - product
                ) % modulus

    return output


def evaluate_polynomial(
    coefficients: Sequence[int],
    point: int,
    modulus: int,
) -> int:
    value = 0

    for coefficient in reversed(coefficients):
        value = (value * point + coefficient) % modulus

    return value


def write_mem(
    path: Path,
    values: Iterable[int],
    hex_width: int = 8,
) -> None:
    with path.open("w", encoding="ascii", newline="\n") as handle:
        for value in values:
            handle.write(f"{value:0{hex_width}x}\n")


def write_schedule(
    path: Path,
    n: int,
    log_n: int,
) -> None:
    with path.open("w", encoding="ascii", newline="") as handle:
        writer = csv.writer(handle)

        writer.writerow(
            (
                "operation",
                "stage",
                "group",
                "j",
                "left_addr",
                "right_addr",
                "twiddle_addr",
            )
        )

        operation = 0

        for stage in range(log_n):
            half = 1 << stage
            span = half << 1
            twiddle_base = half - 1

            for group, group_base in enumerate(range(0, n, span)):
                for j in range(half):
                    writer.writerow(
                        (
                            operation,
                            stage,
                            group,
                            j,
                            group_base + j,
                            group_base + j + half,
                            twiddle_base + j,
                        )
                    )

                    operation += 1


def write_sv_package(
    path: Path,
    *,
    n: int,
    log_n: int,
    modulus: int,
    source_root: int,
    psi: int,
    omega: int,
    psi_inverse: int,
    omega_inverse: int,
    n_inverse: int,
    compact_twiddle_words: int,
    butterflies_per_transform: int,
    forward_multiplications: int,
    inverse_multiplications: int,
    product_multiplications: int,
) -> None:
    text = f"""`timescale 1ns/1ps

package ntt4096_profile_pkg;

    localparam int unsigned NTT_N =
        {n};

    localparam int unsigned NTT_LOG_N =
        {log_n};

    localparam int unsigned NTT_ADDRESS_WIDTH =
        {log_n};

    localparam logic [31:0] NTT_Q =
        32'd{modulus};

    localparam logic [31:0] NTT_SOURCE_ROOT =
        32'd{source_root};

    localparam logic [31:0] NTT_PSI =
        32'd{psi};

    localparam logic [31:0] NTT_OMEGA =
        32'd{omega};

    localparam logic [31:0] NTT_PSI_INVERSE =
        32'd{psi_inverse};

    localparam logic [31:0] NTT_OMEGA_INVERSE =
        32'd{omega_inverse};

    localparam logic [31:0] NTT_N_INVERSE =
        32'd{n_inverse};

    localparam int unsigned NTT_COMPACT_TWIDDLE_WORDS =
        {compact_twiddle_words};

    localparam int unsigned NTT_BUTTERFLIES_PER_TRANSFORM =
        {butterflies_per_transform};

    localparam int unsigned NTT_MODULAR_MULTIPLICATIONS_PER_FORWARD =
        {forward_multiplications};

    localparam int unsigned NTT_MODULAR_MULTIPLICATIONS_PER_INVERSE =
        {inverse_multiplications};

    localparam int unsigned NTT_MODULAR_MULTIPLICATIONS_PER_PRODUCT =
        {product_multiplications};

endpackage
"""

    path.write_text(text, encoding="ascii", newline="\n")


def validate_roots(
    *,
    n: int,
    modulus: int,
    psi: int,
    omega: int,
    psi_inverse: int,
    omega_inverse: int,
    n_inverse: int,
) -> None:
    minus_one = modulus - 1

    checks = (
        (pow(psi, n, modulus), minus_one, "psi^N"),
        (pow(psi, 2 * n, modulus), 1, "psi^(2N)"),
        (pow(omega, n, modulus), 1, "omega^N"),
        (pow(omega, n // 2, modulus), minus_one, "omega^(N/2)"),
        ((psi * psi_inverse) % modulus, 1, "psi*psi_inverse"),
        ((omega * omega_inverse) % modulus, 1, "omega*omega_inverse"),
        ((n * n_inverse) % modulus, 1, "N*N_inverse"),
        ((psi * psi) % modulus, omega, "psi^2"),
    )

    for actual, expected, label in checks:
        if actual != expected:
            raise AssertionError(
                f"Root validation failed for {label}: "
                f"got {actual}, expected {expected}"
            )


def validate_round_trips(
    rng: random.Random,
    tests: int,
    n: int,
    modulus: int,
    twist_factors: Sequence[int],
    inverse_scale_factors: Sequence[int],
    bit_reverse_table: Sequence[int],
    forward_twiddles: Sequence[Sequence[int]],
    inverse_twiddles: Sequence[Sequence[int]],
) -> None:
    for test_number in range(tests):
        coefficients = [rng.randrange(modulus) for _ in range(n)]

        transformed, _, _, _ = forward_negacyclic(
            coefficients,
            twist_factors,
            bit_reverse_table,
            forward_twiddles,
            modulus,
        )

        recovered, _, _, _ = inverse_negacyclic(
            transformed,
            inverse_scale_factors,
            bit_reverse_table,
            inverse_twiddles,
            modulus,
        )

        if recovered != coefficients:
            for index, (actual, expected) in enumerate(
                zip(recovered, coefficients)
            ):
                if actual != expected:
                    raise AssertionError(
                        f"Round trip {test_number} failed at {index}: "
                        f"got {actual}, expected {expected}"
                    )

            raise AssertionError(f"Round trip {test_number} failed")


def validate_sparse_products(
    rng: random.Random,
    tests: int,
    n: int,
    modulus: int,
    twist_factors: Sequence[int],
    inverse_scale_factors: Sequence[int],
    bit_reverse_table: Sequence[int],
    forward_twiddles: Sequence[Sequence[int]],
    inverse_twiddles: Sequence[Sequence[int]],
) -> None:
    nonzero_terms = 32

    for test_number in range(tests):
        a_indices = rng.sample(range(n), nonzero_terms)
        b_indices = rng.sample(range(n), nonzero_terms)

        a_entries = [
            (index, rng.randrange(1, modulus))
            for index in a_indices
        ]

        b_entries = [
            (index, rng.randrange(1, modulus))
            for index in b_indices
        ]

        a = [0] * n
        b = [0] * n

        for index, value in a_entries:
            a[index] = value

        for index, value in b_entries:
            b[index] = value

        expected = sparse_negacyclic_reference(
            a_entries,
            b_entries,
            n,
            modulus,
        )

        actual = polynomial_product(
            a,
            b,
            twist_factors,
            inverse_scale_factors,
            bit_reverse_table,
            forward_twiddles,
            inverse_twiddles,
            modulus,
        )

        if actual != expected:
            for index, (actual_value, expected_value) in enumerate(
                zip(actual, expected)
            ):
                if actual_value != expected_value:
                    raise AssertionError(
                        f"Sparse product {test_number} failed at {index}: "
                        f"got {actual_value}, expected {expected_value}"
                    )

            raise AssertionError(
                f"Sparse product {test_number} failed"
            )


def validate_dense_products_by_evaluation(
    rng: random.Random,
    tests: int,
    n: int,
    modulus: int,
    psi: int,
    twist_factors: Sequence[int],
    inverse_scale_factors: Sequence[int],
    bit_reverse_table: Sequence[int],
    forward_twiddles: Sequence[Sequence[int]],
    inverse_twiddles: Sequence[Sequence[int]],
) -> None:
    evaluation_points_per_test = 8

    for test_number in range(tests):
        a = [rng.randrange(modulus) for _ in range(n)]
        b = [rng.randrange(modulus) for _ in range(n)]

        product = polynomial_product(
            a,
            b,
            twist_factors,
            inverse_scale_factors,
            bit_reverse_table,
            forward_twiddles,
            inverse_twiddles,
            modulus,
        )

        selected_indices = rng.sample(
            range(n),
            evaluation_points_per_test,
        )

        for selected_index in selected_indices:
            point = pow(
                psi,
                2 * selected_index + 1,
                modulus,
            )

            if pow(point, n, modulus) != modulus - 1:
                raise AssertionError(
                    f"Evaluation point is not a root of X^N+1: "
                    f"test={test_number}, index={selected_index}"
                )

            evaluated_a = evaluate_polynomial(
                a,
                point,
                modulus,
            )

            evaluated_b = evaluate_polynomial(
                b,
                point,
                modulus,
            )

            evaluated_product = evaluate_polynomial(
                product,
                point,
                modulus,
            )

            expected = (
                evaluated_a
                * evaluated_b
            ) % modulus

            if evaluated_product != expected:
                raise AssertionError(
                    f"Dense evaluation failed: test={test_number}, "
                    f"root_index={selected_index}, "
                    f"got={evaluated_product}, expected={expected}"
                )


def main() -> None:
    args = parse_args()
    profile = load_profile(args.profile)

    n = int(profile["ring_dimension"])
    cyclotomic_order = int(profile["cyclotomic_order"])
    modulus = int(profile["modulus"])

    source_n = int(profile["source_ring_dimension"])
    source_cyclotomic_order = int(
        profile["source_cyclotomic_order"]
    )

    source_root = int(profile["source_root"])
    input_seed = int(profile["input_seed"])

    require_power_of_two(n, "ring_dimension")
    require_power_of_two(source_n, "source_ring_dimension")

    if cyclotomic_order != 2 * n:
        raise ValueError(
            f"cyclotomic_order must equal 2*N; "
            f"got {cyclotomic_order} and N={n}"
        )

    if source_cyclotomic_order != 2 * source_n:
        raise ValueError(
            "source_cyclotomic_order must equal "
            "2*source_ring_dimension"
        )

    if n > source_n or source_n % n != 0:
        raise ValueError(
            f"N={n} must divide source N={source_n}"
        )

    log_n = n.bit_length() - 1
    root_exponent = source_n // n

    psi = pow(
        source_root,
        root_exponent,
        modulus,
    )

    omega = pow(psi, 2, modulus)
    psi_inverse = pow(psi, -1, modulus)
    omega_inverse = pow(omega, -1, modulus)
    n_inverse = pow(n, -1, modulus)

    validate_roots(
        n=n,
        modulus=modulus,
        psi=psi,
        omega=omega,
        psi_inverse=psi_inverse,
        omega_inverse=omega_inverse,
        n_inverse=n_inverse,
    )

    bit_reverse_table = make_bit_reverse_table(
        n,
        log_n,
    )

    twist_factors = powers(
        psi,
        n,
        modulus,
    )

    inverse_psi_powers = powers(
        psi_inverse,
        n,
        modulus,
    )

    inverse_scale_factors = [
        (n_inverse * value) % modulus
        for value in inverse_psi_powers
    ]

    forward_twiddles = make_stage_twiddles(
        omega,
        n,
        log_n,
        modulus,
    )

    inverse_twiddles = make_stage_twiddles(
        omega_inverse,
        n,
        log_n,
        modulus,
    )

    compact_twiddle_words = n - 1
    butterflies_per_transform = (n // 2) * log_n
    forward_multiplications = n + butterflies_per_transform
    inverse_multiplications = butterflies_per_transform + n
    product_multiplications = (
        2 * forward_multiplications
        + n
        + inverse_multiplications
    )

    flat_forward_twiddles = flatten_stages(
        forward_twiddles
    )

    flat_inverse_twiddles = flatten_stages(
        inverse_twiddles
    )

    if len(flat_forward_twiddles) != compact_twiddle_words:
        raise AssertionError(
            "Incorrect forward compact twiddle count"
        )

    if len(flat_inverse_twiddles) != compact_twiddle_words:
        raise AssertionError(
            "Incorrect inverse compact twiddle count"
        )

    validation_rng = random.Random(args.seed)

    validate_round_trips(
        validation_rng,
        args.roundtrip_tests,
        n,
        modulus,
        twist_factors,
        inverse_scale_factors,
        bit_reverse_table,
        forward_twiddles,
        inverse_twiddles,
    )

    validate_sparse_products(
        validation_rng,
        args.sparse_convolution_tests,
        n,
        modulus,
        twist_factors,
        inverse_scale_factors,
        bit_reverse_table,
        forward_twiddles,
        inverse_twiddles,
    )

    validate_dense_products_by_evaluation(
        validation_rng,
        args.dense_evaluation_tests,
        n,
        modulus,
        psi,
        twist_factors,
        inverse_scale_factors,
        bit_reverse_table,
        forward_twiddles,
        inverse_twiddles,
    )

    args.output.mkdir(
        parents=True,
        exist_ok=True,
    )

    vector_rng = random.Random(input_seed)

    input_a = [
        vector_rng.randrange(modulus)
        for _ in range(n)
    ]

    input_b = [
        vector_rng.randrange(modulus)
        for _ in range(n)
    ]

    (
        forward_a,
        twisted_a,
        bit_reversed_a,
        forward_a_stages,
    ) = forward_negacyclic(
        input_a,
        twist_factors,
        bit_reverse_table,
        forward_twiddles,
        modulus,
        capture_stages=True,
    )

    (
        forward_b,
        twisted_b,
        bit_reversed_b,
        forward_b_stages,
    ) = forward_negacyclic(
        input_b,
        twist_factors,
        bit_reverse_table,
        forward_twiddles,
        modulus,
        capture_stages=True,
    )

    pointwise = [
        (left * right) % modulus
        for left, right in zip(
            forward_a,
            forward_b,
        )
    ]

    (
        convolution,
        inverse_cyclic,
        inverse_bit_reversed,
        inverse_stages,
    ) = inverse_negacyclic(
        pointwise,
        inverse_scale_factors,
        bit_reverse_table,
        inverse_twiddles,
        modulus,
        capture_stages=True,
    )

    write_mem(
        args.output / "input_a.mem",
        input_a,
    )

    write_mem(
        args.output / "input_b.mem",
        input_b,
    )

    write_mem(
        args.output / "twist_factors.mem",
        twist_factors,
    )

    write_mem(
        args.output / "inverse_scale_factors.mem",
        inverse_scale_factors,
    )

    write_mem(
        args.output / "bit_reverse.mem",
        bit_reverse_table,
        hex_width=3,
    )

    write_mem(
        args.output / "forward_twiddles.mem",
        flat_forward_twiddles,
    )

    write_mem(
        args.output / "inverse_twiddles.mem",
        flat_inverse_twiddles,
    )

    write_mem(
        args.output / "forward_a_twisted_natural.mem",
        twisted_a,
    )

    write_mem(
        args.output / "forward_a_bit_reversed.mem",
        bit_reversed_a,
    )

    for stage, values in enumerate(forward_a_stages):
        write_mem(
            args.output / f"forward_a_stage{stage}.mem",
            values,
        )

    write_mem(
        args.output / "forward_a.mem",
        forward_a,
    )

    write_mem(
        args.output / "forward_b_twisted_natural.mem",
        twisted_b,
    )

    write_mem(
        args.output / "forward_b_bit_reversed.mem",
        bit_reversed_b,
    )

    for stage, values in enumerate(forward_b_stages):
        write_mem(
            args.output / f"forward_b_stage{stage}.mem",
            values,
        )

    write_mem(
        args.output / "forward_b.mem",
        forward_b,
    )

    write_mem(
        args.output / "pointwise.mem",
        pointwise,
    )

    write_mem(
        args.output / "inverse_product_bit_reversed.mem",
        inverse_bit_reversed,
    )

    for stage, values in enumerate(inverse_stages):
        write_mem(
            args.output / f"inverse_product_stage{stage}.mem",
            values,
        )

    write_mem(
        args.output / "inverse_product_cyclic.mem",
        inverse_cyclic,
    )

    write_mem(
        args.output / "convolution.mem",
        convolution,
    )

    write_schedule(
        args.output / "butterfly_schedule.csv",
        n,
        log_n,
    )

    write_sv_package(
        args.output / "ntt4096_profile_pkg.sv",
        n=n,
        log_n=log_n,
        modulus=modulus,
        source_root=source_root,
        psi=psi,
        omega=omega,
        psi_inverse=psi_inverse,
        omega_inverse=omega_inverse,
        n_inverse=n_inverse,
        compact_twiddle_words=compact_twiddle_words,
        butterflies_per_transform=butterflies_per_transform,
        forward_multiplications=forward_multiplications,
        inverse_multiplications=inverse_multiplications,
        product_multiplications=product_multiplications,
    )

    generated_profile = dict(profile)
    generated_profile.update(
        {
            "log2_ring_dimension": log_n,
            "root_exponent_from_source": root_exponent,
            "psi": psi,
            "omega": omega,
            "psi_inverse": psi_inverse,
            "omega_inverse": omega_inverse,
            "n_inverse": n_inverse,
            "compact_twiddle_words_per_direction":
                compact_twiddle_words,
            "butterflies_per_transform":
                butterflies_per_transform,
            "modular_multiplications_per_forward_transform":
                forward_multiplications,
            "modular_multiplications_per_inverse_transform":
                inverse_multiplications,
            "modular_multiplications_per_product":
                product_multiplications,
            "hardware_convention": {
                "forward_twist": "a[j] * psi^j",
                "input_placement": "bit_reverse(j)",
                "cyclic_transform": "radix-2 DIT",
                "transform_output_order": "natural",
                "inverse_postscale": "N^-1 * psi^-j",
                "twiddle_layout": "stage-major compact",
                "stage_s_twiddle_base": "2^s - 1",
            },
        }
    )

    (
        args.output / "profile.json"
    ).write_text(
        json.dumps(
            generated_profile,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )

    summary_lines = [
        f"N={n}",
        f"log2(N)={log_n}",
        f"q={modulus}",
        f"source_root={source_root}",
        f"psi={psi}",
        f"omega={omega}",
        f"psi_inverse={psi_inverse}",
        f"omega_inverse={omega_inverse}",
        f"n_inverse={n_inverse}",
        (
            "compact_twiddle_words_per_direction="
            f"{compact_twiddle_words}"
        ),
        (
            "butterflies_per_transform="
            f"{butterflies_per_transform}"
        ),
        (
            "modular_multiplications_per_forward_transform="
            f"{forward_multiplications}"
        ),
        (
            "modular_multiplications_per_inverse_transform="
            f"{inverse_multiplications}"
        ),
        (
            "modular_multiplications_per_product="
            f"{product_multiplications}"
        ),
    ]

    (
        args.output / "summary.txt"
    ).write_text(
        "\n".join(summary_lines) + "\n",
        encoding="ascii",
        newline="\n",
    )

    print("PASS: OpenFHE-derived N=4096 roots validated")
    print(
        f"PASS: {args.roundtrip_tests} randomized "
        "N=4096 NTT round trips"
    )
    print(
        f"PASS: {args.sparse_convolution_tests} sparse exact "
        "N=4096 negacyclic convolutions"
    )
    print(
        f"PASS: {args.dense_evaluation_tests} dense N=4096 products "
        "passed root-evaluation checks"
    )

    for line in summary_lines:
        print(line)

    print(f"generated_dir={args.output}")


if __name__ == "__main__":
    main()
