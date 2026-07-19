#!/usr/bin/env python3

from __future__ import annotations

import csv
import json
import random
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = ROOT / "model" / "golden_n256"
PROFILE_PATH = (
    ROOT
    / "profiles"
    / "openfhe-ckks-tower0-n256.json"
)

SOURCE_RING_DIMENSION = 4096
SOURCE_CYCLOTOMIC_ORDER = 8192

N = 256
LOG_N = 8
CYCLOTOMIC_ORDER = 2 * N

Q = 1073692673
SOURCE_ROOT = 236231

RANDOM_ROUND_TRIPS = 100
RANDOM_CONVOLUTIONS = 100
RANDOM_SEED = 0x00C0FFEE


def bit_reverse(value: int, width: int) -> int:
    result = 0

    for bit_index in range(width):
        result <<= 1
        result |= (value >> bit_index) & 1

    return result


def compact_twiddle_rom(root: int) -> list[int]:
    """
    Store only the distinct twiddles required by each stage.

    Stage s contains 2**s words and begins at address:

        stage_base = 2**s - 1

    Total words:

        1 + 2 + 4 + ... + N/2 = N - 1
    """

    words: list[int] = []

    for stage in range(LOG_N):
        half = 1 << stage
        step = N >> (stage + 1)

        for local_index in range(half):
            words.append(
                pow(
                    root,
                    local_index * step,
                    Q,
                )
            )

    if len(words) != N - 1:
        raise RuntimeError(
            f"Twiddle ROM contains {len(words)} words; "
            f"expected {N - 1}"
        )

    return words


def cyclic_ntt(
    natural_input: list[int],
    root: int,
) -> tuple[list[int], list[list[int]], list[int]]:
    """
    Radix-2 DIT transform matching the existing N=16 hardware:

      1. bit-reverse input placement
      2. in-place radix-2 stages
      3. natural-order output
    """

    if len(natural_input) != N:
        raise ValueError(
            f"Expected {N} coefficients; "
            f"received {len(natural_input)}"
        )

    memory = [0] * N

    for natural_address, value in enumerate(natural_input):
        reversed_address = bit_reverse(
            natural_address,
            LOG_N,
        )

        memory[reversed_address] = value % Q

    bit_reversed_input = memory.copy()
    stage_snapshots: list[list[int]] = []

    for stage in range(LOG_N):
        half = 1 << stage
        block_size = half << 1
        twiddle_step = N // block_size

        for block_base in range(0, N, block_size):
            for local_index in range(half):
                address_a = block_base + local_index
                address_b = address_a + half

                twiddle = pow(
                    root,
                    local_index * twiddle_step,
                    Q,
                )

                value_a = memory[address_a]
                value_b = memory[address_b]

                product = (
                    twiddle * value_b
                ) % Q

                memory[address_a] = (
                    value_a + product
                ) % Q

                memory[address_b] = (
                    value_a - product
                ) % Q

        stage_snapshots.append(memory.copy())

    return (
        bit_reversed_input,
        stage_snapshots,
        memory.copy(),
    )


def forward_negacyclic_ntt(
    coefficients: list[int],
) -> tuple[
    list[int],
    list[int],
    list[list[int]],
    list[int],
]:
    twisted = [
        (
            coefficient
            * pow(PSI, index, Q)
        )
        % Q
        for index, coefficient in enumerate(coefficients)
    ]

    (
        bit_reversed_input,
        stage_snapshots,
        transformed,
    ) = cyclic_ntt(
        twisted,
        OMEGA,
    )

    return (
        twisted,
        bit_reversed_input,
        stage_snapshots,
        transformed,
    )


def inverse_negacyclic_ntt(
    transformed: list[int],
) -> tuple[
    list[int],
    list[list[int]],
    list[int],
]:
    (
        bit_reversed_input,
        stage_snapshots,
        cyclic_inverse,
    ) = cyclic_ntt(
        transformed,
        OMEGA_INVERSE,
    )

    coefficients = [
        (
            cyclic_inverse[index]
            * N_INVERSE
            * pow(PSI_INVERSE, index, Q)
        )
        % Q
        for index in range(N)
    ]

    return (
        bit_reversed_input,
        stage_snapshots,
        coefficients,
    )


def negacyclic_schoolbook(
    left: list[int],
    right: list[int],
) -> list[int]:
    result = [0] * N

    for left_index, left_value in enumerate(left):
        for right_index, right_value in enumerate(right):
            destination = left_index + right_index

            product = (
                left_value * right_value
            ) % Q

            if destination < N:
                result[destination] = (
                    result[destination] + product
                ) % Q
            else:
                destination -= N

                result[destination] = (
                    result[destination] - product
                ) % Q

    return result


def write_mem(
    path: Path,
    values: list[int],
    hex_digits: int = 8,
) -> None:
    text = "".join(
        f"{value:0{hex_digits}x}\n"
        for value in values
    )

    path.write_text(
        text,
        encoding="ascii",
    )


def write_stage_files(
    prefix: str,
    stages: list[list[int]],
) -> None:
    for stage_index, values in enumerate(stages):
        write_mem(
            OUTPUT_DIR
            / f"{prefix}_stage{stage_index}.mem",
            values,
        )


def write_schedule(
    forward_twiddles: list[int],
    inverse_twiddles: list[int],
) -> None:
    path = OUTPUT_DIR / "butterfly_schedule.csv"

    with path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as handle:
        writer = csv.writer(handle)

        writer.writerow(
            [
                "operation_index",
                "stage",
                "butterfly_in_stage",
                "half",
                "block",
                "local_index",
                "address_a",
                "address_b",
                "twiddle_address",
                "forward_twiddle",
                "inverse_twiddle",
            ]
        )

        operation_index = 0

        for stage in range(LOG_N):
            half = 1 << stage
            block_size = half << 1
            stage_base = (1 << stage) - 1

            for butterfly_index in range(N // 2):
                block = butterfly_index // half
                local_index = butterfly_index % half

                address_a = (
                    block * block_size
                    + local_index
                )

                address_b = address_a + half
                twiddle_address = (
                    stage_base + local_index
                )

                writer.writerow(
                    [
                        operation_index,
                        stage,
                        butterfly_index,
                        half,
                        block,
                        local_index,
                        address_a,
                        address_b,
                        twiddle_address,
                        forward_twiddles[
                            twiddle_address
                        ],
                        inverse_twiddles[
                            twiddle_address
                        ],
                    ]
                )

                operation_index += 1

        if operation_index != BUTTERFLIES_PER_TRANSFORM:
            raise RuntimeError(
                f"Schedule contains {operation_index} butterflies; "
                f"expected {BUTTERFLIES_PER_TRANSFORM}"
            )


def write_profile_package() -> None:
    package_path = (
        OUTPUT_DIR
        / "ntt256_profile_pkg.sv"
    )

    package_path.write_text(
        f"""package ntt256_profile_pkg;

    localparam integer NTT_N = {N};
    localparam integer NTT_LOG_N = {LOG_N};
    localparam integer NTT_ADDRESS_WIDTH = {LOG_N};
    localparam integer NTT_TWIDDLE_WORDS = {N - 1};
    localparam integer NTT_TWIDDLE_ADDRESS_WIDTH = 8;
    localparam integer NTT_BUTTERFLIES = {BUTTERFLIES_PER_TRANSFORM};

    localparam logic [31:0] NTT_Q =
        32'd{Q};

    localparam logic [31:0] NTT_PSI =
        32'd{PSI};

    localparam logic [31:0] NTT_OMEGA =
        32'd{OMEGA};

    localparam logic [31:0] NTT_PSI_INVERSE =
        32'd{PSI_INVERSE};

    localparam logic [31:0] NTT_OMEGA_INVERSE =
        32'd{OMEGA_INVERSE};

    localparam logic [31:0] NTT_N_INVERSE =
        32'd{N_INVERSE};

endpackage
""",
        encoding="ascii",
    )


DERIVATION_EXPONENT = (
    SOURCE_CYCLOTOMIC_ORDER
    // CYCLOTOMIC_ORDER
)

PSI = pow(
    SOURCE_ROOT,
    DERIVATION_EXPONENT,
    Q,
)

OMEGA = pow(
    PSI,
    2,
    Q,
)

PSI_INVERSE = pow(
    PSI,
    -1,
    Q,
)

OMEGA_INVERSE = pow(
    OMEGA,
    -1,
    Q,
)

N_INVERSE = pow(
    N,
    -1,
    Q,
)

BUTTERFLIES_PER_TRANSFORM = (
    (N // 2) * LOG_N
)

FORWARD_MODULAR_MULTIPLICATIONS = (
    N + BUTTERFLIES_PER_TRANSFORM
)

INVERSE_MODULAR_MULTIPLICATIONS = (
    BUTTERFLIES_PER_TRANSFORM + N
)

MODULAR_MULTIPLICATIONS_PER_PRODUCT = (
    2 * FORWARD_MODULAR_MULTIPLICATIONS
    + N
    + INVERSE_MODULAR_MULTIPLICATIONS
)


def validate_roots() -> None:
    if N != 1 << LOG_N:
        raise RuntimeError(
            "N is not a power of two"
        )

    if (
        SOURCE_CYCLOTOMIC_ORDER
        % CYCLOTOMIC_ORDER
    ) != 0:
        raise RuntimeError(
            "Source root order cannot derive requested profile"
        )

    if pow(SOURCE_ROOT, SOURCE_CYCLOTOMIC_ORDER, Q) != 1:
        raise RuntimeError(
            "OpenFHE source root has incorrect order"
        )

    if pow(
        SOURCE_ROOT,
        SOURCE_CYCLOTOMIC_ORDER // 2,
        Q,
    ) != Q - 1:
        raise RuntimeError(
            "OpenFHE source root is not primitive"
        )

    if pow(PSI, 2 * N, Q) != 1:
        raise RuntimeError(
            "psi^(2N) is not one"
        )

    if pow(PSI, N, Q) != Q - 1:
        raise RuntimeError(
            "psi^N is not minus one"
        )

    if pow(OMEGA, N, Q) != 1:
        raise RuntimeError(
            "omega^N is not one"
        )

    if pow(OMEGA, N // 2, Q) != Q - 1:
        raise RuntimeError(
            "omega does not have exact order N"
        )

    if (PSI * PSI_INVERSE) % Q != 1:
        raise RuntimeError(
            "psi inverse is invalid"
        )

    if (OMEGA * OMEGA_INVERSE) % Q != 1:
        raise RuntimeError(
            "omega inverse is invalid"
        )

    if (N * N_INVERSE) % Q != 1:
        raise RuntimeError(
            "N inverse is invalid"
        )


def main() -> None:
    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    PROFILE_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    validate_roots()

    forward_twiddles = compact_twiddle_rom(
        OMEGA
    )

    inverse_twiddles = compact_twiddle_rom(
        OMEGA_INVERSE
    )

    twist_factors = [
        pow(PSI, index, Q)
        for index in range(N)
    ]

    inverse_scale_factors = [
        (
            N_INVERSE
            * pow(PSI_INVERSE, index, Q)
        )
        % Q
        for index in range(N)
    ]

    bit_reverse_addresses = [
        bit_reverse(index, LOG_N)
        for index in range(N)
    ]

    input_a = [
        index + 1
        for index in range(N)
    ]

    input_b = [
        (
            (index + 3)
            * (index + 11)
            + 17
        )
        % Q
        for index in range(N)
    ]

    (
        twisted_a,
        forward_a_bit_reversed,
        forward_a_stages,
        forward_a,
    ) = forward_negacyclic_ntt(input_a)

    (
        twisted_b,
        forward_b_bit_reversed,
        forward_b_stages,
        forward_b,
    ) = forward_negacyclic_ntt(input_b)

    pointwise = [
        (
            forward_a[index]
            * forward_b[index]
        )
        % Q
        for index in range(N)
    ]

    (
        inverse_product_bit_reversed,
        inverse_product_stages,
        convolution,
    ) = inverse_negacyclic_ntt(pointwise)

    schoolbook = negacyclic_schoolbook(
        input_a,
        input_b,
    )

    if convolution != schoolbook:
        raise RuntimeError(
            "Golden NTT convolution does not match schoolbook"
        )

    write_mem(
        OUTPUT_DIR / "input_a.mem",
        input_a,
    )

    write_mem(
        OUTPUT_DIR / "input_b.mem",
        input_b,
    )

    write_mem(
        OUTPUT_DIR / "twist_factors.mem",
        twist_factors,
    )

    write_mem(
        OUTPUT_DIR / "inverse_scale_factors.mem",
        inverse_scale_factors,
    )

    write_mem(
        OUTPUT_DIR / "bit_reverse.mem",
        bit_reverse_addresses,
        hex_digits=2,
    )

    write_mem(
        OUTPUT_DIR / "forward_twiddles.mem",
        forward_twiddles,
    )

    write_mem(
        OUTPUT_DIR / "inverse_twiddles.mem",
        inverse_twiddles,
    )

    write_mem(
        OUTPUT_DIR / "twisted_a.mem",
        twisted_a,
    )

    write_mem(
        OUTPUT_DIR
        / "forward_a_bit_reversed_input.mem",
        forward_a_bit_reversed,
    )

    write_stage_files(
        "forward_a",
        forward_a_stages,
    )

    write_mem(
        OUTPUT_DIR / "forward_a.mem",
        forward_a,
    )

    write_mem(
        OUTPUT_DIR / "twisted_b.mem",
        twisted_b,
    )

    write_mem(
        OUTPUT_DIR
        / "forward_b_bit_reversed_input.mem",
        forward_b_bit_reversed,
    )

    write_stage_files(
        "forward_b",
        forward_b_stages,
    )

    write_mem(
        OUTPUT_DIR / "forward_b.mem",
        forward_b,
    )

    write_mem(
        OUTPUT_DIR / "pointwise.mem",
        pointwise,
    )

    write_mem(
        OUTPUT_DIR
        / "inverse_product_bit_reversed_input.mem",
        inverse_product_bit_reversed,
    )

    write_stage_files(
        "inverse_product",
        inverse_product_stages,
    )

    write_mem(
        OUTPUT_DIR / "convolution.mem",
        convolution,
    )

    write_schedule(
        forward_twiddles,
        inverse_twiddles,
    )

    write_profile_package()

    profile = {
        "name": "openfhe-ckks-tower0-n256",
        "source": {
            "ring_dimension": SOURCE_RING_DIMENSION,
            "cyclotomic_order": SOURCE_CYCLOTOMIC_ORDER,
            "tower_index": 0,
            "modulus": Q,
            "root_of_unity": SOURCE_ROOT,
        },
        "hardware": {
            "n": N,
            "log_n": LOG_N,
            "cyclotomic_order": CYCLOTOMIC_ORDER,
            "derivation_exponent": DERIVATION_EXPONENT,
            "psi": PSI,
            "omega": OMEGA,
            "psi_inverse": PSI_INVERSE,
            "omega_inverse": OMEGA_INVERSE,
            "n_inverse": N_INVERSE,
            "twiddle_words_per_direction": N - 1,
            "butterflies_per_transform": (
                BUTTERFLIES_PER_TRANSFORM
            ),
            "forward_modular_multiplications": (
                FORWARD_MODULAR_MULTIPLICATIONS
            ),
            "inverse_modular_multiplications": (
                INVERSE_MODULAR_MULTIPLICATIONS
            ),
            "modular_multiplications_per_product": (
                MODULAR_MULTIPLICATIONS_PER_PRODUCT
            ),
        },
        "convention": {
            "ring": "Z_q[X]/(X^256+1)",
            "forward_twist": "a[j] * psi^j mod q",
            "cyclic_input_order": "bit-reversed",
            "cyclic_output_order": "natural",
            "cyclic_algorithm": "radix-2 DIT",
            "butterfly": [
                "t = twiddle * b mod q",
                "out_a = a + t mod q",
                "out_b = a - t mod q",
            ],
            "inverse_postprocess": (
                "value[j] * N^-1 * psi^-j mod q"
            ),
            "twiddle_rom_layout": (
                "stage-major; stage s begins at 2^s-1 "
                "and contains 2^s words"
            ),
        },
    }

    PROFILE_PATH.write_text(
        json.dumps(
            profile,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    rng = random.Random(RANDOM_SEED)

    for test_index in range(RANDOM_ROUND_TRIPS):
        coefficients = [
            rng.randrange(Q)
            for _ in range(N)
        ]

        transformed = forward_negacyclic_ntt(
            coefficients
        )[3]

        recovered = inverse_negacyclic_ntt(
            transformed
        )[2]

        if recovered != coefficients:
            raise RuntimeError(
                f"Round trip failed at test {test_index}"
            )

    for test_index in range(RANDOM_CONVOLUTIONS):
        left = [
            rng.randrange(Q)
            for _ in range(N)
        ]

        right = [
            rng.randrange(Q)
            for _ in range(N)
        ]

        transformed_left = forward_negacyclic_ntt(
            left
        )[3]

        transformed_right = forward_negacyclic_ntt(
            right
        )[3]

        transformed_product = [
            (
                transformed_left[index]
                * transformed_right[index]
            )
            % Q
            for index in range(N)
        ]

        ntt_product = inverse_negacyclic_ntt(
            transformed_product
        )[2]

        reference_product = negacyclic_schoolbook(
            left,
            right,
        )

        if ntt_product != reference_product:
            raise RuntimeError(
                f"Convolution failed at test {test_index}"
            )

    print("PASS: OpenFHE-derived N=256 roots validated")
    print(
        f"PASS: {RANDOM_ROUND_TRIPS} randomized "
        "N=256 NTT round trips"
    )
    print(
        f"PASS: {RANDOM_CONVOLUTIONS} randomized "
        "N=256 negacyclic convolutions"
    )
    print(f"N={N}")
    print(f"log2(N)={LOG_N}")
    print(f"q={Q}")
    print(f"source_root={SOURCE_ROOT}")
    print(f"psi={PSI}")
    print(f"omega={OMEGA}")
    print(f"psi_inverse={PSI_INVERSE}")
    print(f"omega_inverse={OMEGA_INVERSE}")
    print(f"n_inverse={N_INVERSE}")
    print(
        "compact_twiddle_words_per_direction="
        f"{N - 1}"
    )
    print(
        "butterflies_per_transform="
        f"{BUTTERFLIES_PER_TRANSFORM}"
    )
    print(
        "modular_multiplications_per_product="
        f"{MODULAR_MULTIPLICATIONS_PER_PRODUCT}"
    )
    print(f"profile={PROFILE_PATH}")
    print(f"golden_directory={OUTPUT_DIR}")


if __name__ == "__main__":
    main()
