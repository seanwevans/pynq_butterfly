#!/usr/bin/env python3

import csv
import json
import math
import random
from pathlib import Path
from typing import Any


PROFILE_PATH = Path(
    "/mnt/f/repos/openfhe-param-export/"
    "profiles/openfhe-ckks-tower0-n16.json"
)

OUTPUT_DIR = Path("golden")

RANDOM_TESTS = 1000
RANDOM_SEED = 0xC0FFEE


def bit_reverse(value: int, width: int) -> int:
    result = 0

    for _ in range(width):
        result = (result << 1) | (value & 1)
        value >>= 1

    return result


def require_reduced(
    values: list[int],
    q: int,
    name: str,
) -> None:
    for index, value in enumerate(values):
        if not 0 <= value < q:
            raise ValueError(
                f"{name}[{index}]={value} is outside [0, {q})"
            )


def cyclic_ntt_dit_trace(
    values: list[int],
    root: int,
    q: int,
) -> tuple[list[int], dict[str, Any]]:
    """
    Radix-2 decimation-in-time cyclic NTT.

    Input is explicitly bit-reversed.
    Output is in natural order.

    Butterfly:
        t     = twiddle * b mod q
        out_a = a + t mod q
        out_b = a - t mod q
    """

    n = len(values)

    if n < 2 or (n & (n - 1)) != 0:
        raise ValueError(
            "NTT length must be a power of two"
        )

    require_reduced(values, q, "values")

    width = int(math.log2(n))

    permutation = [
        bit_reverse(index, width)
        for index in range(n)
    ]

    memory = [
        values[index]
        for index in permutation
    ]

    trace: dict[str, Any] = {
        "input": values.copy(),
        "bit_reverse_permutation": permutation,
        "bit_reversed_input": memory.copy(),
        "stages": [],
    }

    for stage in range(width):
        span = 1 << (stage + 1)
        half_span = span >> 1

        stage_root = pow(
            root,
            n // span,
            q,
        )

        butterflies: list[dict[str, int]] = []
        butterfly_number = 0

        for block in range(0, n, span):
            twiddle = 1

            for offset in range(half_span):
                index_a = block + offset
                index_b = index_a + half_span

                input_a = memory[index_a]
                input_b = memory[index_b]

                product = (
                    twiddle * input_b
                ) % q

                output_a = (
                    input_a + product
                ) % q

                output_b = (
                    input_a - product
                ) % q

                memory[index_a] = output_a
                memory[index_b] = output_b

                butterflies.append(
                    {
                        "butterfly": butterfly_number,
                        "index_a": index_a,
                        "index_b": index_b,
                        "twiddle": twiddle,
                        "input_a": input_a,
                        "input_b": input_b,
                        "product": product,
                        "output_a": output_a,
                        "output_b": output_b,
                    }
                )

                butterfly_number += 1

                twiddle = (
                    twiddle * stage_root
                ) % q

        trace["stages"].append(
            {
                "stage": stage,
                "span": span,
                "half_span": half_span,
                "stage_root": stage_root,
                "butterflies": butterflies,
                "memory_after": memory.copy(),
            }
        )

    trace["output"] = memory.copy()

    return memory, trace


def forward_negacyclic_trace(
    values: list[int],
    psi: int,
    omega: int,
    q: int,
) -> tuple[list[int], dict[str, Any]]:
    """
    Negacyclic NTT for Z_q[X] / (X^N + 1).

    First twist:
        twisted[j] = input[j] * psi^j mod q

    Then apply a cyclic NTT using:
        omega = psi^2
    """

    n = len(values)

    require_reduced(
        values,
        q,
        "forward input",
    )

    twist_factors = [
        pow(psi, index, q)
        for index in range(n)
    ]

    twisted = [
        (
            value *
            twist_factors[index]
        ) % q
        for index, value in enumerate(values)
    ]

    output, cyclic_trace = cyclic_ntt_dit_trace(
        twisted,
        omega,
        q,
    )

    return output, {
        "input": values.copy(),
        "twist_factors": twist_factors,
        "twisted_input": twisted,
        "cyclic_ntt": cyclic_trace,
        "output": output.copy(),
    }


def inverse_negacyclic_trace(
    values: list[int],
    psi_inverse: int,
    omega_inverse: int,
    n_inverse: int,
    q: int,
) -> tuple[list[int], dict[str, Any]]:
    """
    Inverse negacyclic NTT.

    Apply the inverse cyclic NTT, then:

        output[j] =
            cyclic_output[j]
            * N^-1
            * psi^(-j)
            mod q
    """

    n = len(values)

    require_reduced(
        values,
        q,
        "inverse input",
    )

    cyclic_output, cyclic_trace = cyclic_ntt_dit_trace(
        values,
        omega_inverse,
        q,
    )

    scale_factors = [
        (
            n_inverse *
            pow(psi_inverse, index, q)
        ) % q
        for index in range(n)
    ]

    output = [
        (
            cyclic_output[index] *
            scale_factors[index]
        ) % q
        for index in range(n)
    ]

    return output, {
        "input": values.copy(),
        "cyclic_inverse_ntt": cyclic_trace,
        "unscaled_twisted_output": cyclic_output,
        "scale_and_untwist_factors": scale_factors,
        "output": output.copy(),
    }


def schoolbook_negacyclic(
    left: list[int],
    right: list[int],
    q: int,
) -> list[int]:
    """
    Reference multiplication modulo X^N + 1.

    Terms whose degree reaches N wrap around with
    a negative sign because X^N = -1.
    """

    if len(left) != len(right):
        raise ValueError(
            "Polynomial lengths differ"
        )

    n = len(left)
    output = [0] * n

    for i, left_value in enumerate(left):
        for j, right_value in enumerate(right):
            product = (
                left_value * right_value
            ) % q

            destination = i + j

            if destination < n:
                output[destination] = (
                    output[destination] +
                    product
                ) % q
            else:
                output[destination - n] = (
                    output[destination - n] -
                    product
                ) % q

    return output


def write_mem(
    path: Path,
    values: list[int],
) -> None:
    """
    Write one 32-bit hexadecimal coefficient per line.

    These files can later be loaded with SystemVerilog:
        $readmemh(...)
    """

    path.write_text(
        "".join(
            f"{value:08x}\n"
            for value in values
        ),
        encoding="utf-8",
    )


def write_schedule(
    path: Path,
    trace: dict[str, Any],
) -> None:
    """
    Emit the exact controller schedule, independent of data.

    One row corresponds to one butterfly command.
    """

    with path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as handle:
        writer = csv.writer(handle)

        writer.writerow(
            [
                "stage",
                "butterfly",
                "index_a",
                "index_b",
                "twiddle",
            ]
        )

        for stage in trace["stages"]:
            for butterfly in stage["butterflies"]:
                writer.writerow(
                    [
                        stage["stage"],
                        butterfly["butterfly"],
                        butterfly["index_a"],
                        butterfly["index_b"],
                        butterfly["twiddle"],
                    ]
                )


def write_trace_memories(
    prefix: str,
    trace: dict[str, Any],
) -> None:
    write_mem(
        OUTPUT_DIR /
        f"{prefix}_bit_reversed_input.mem",
        trace["bit_reversed_input"],
    )

    for stage in trace["stages"]:
        write_mem(
            OUTPUT_DIR /
            f"{prefix}_stage{stage['stage']}.mem",
            stage["memory_after"],
        )


def main() -> None:
    if not PROFILE_PATH.is_file():
        raise FileNotFoundError(
            f"Missing OpenFHE profile: {PROFILE_PATH}"
        )

    profile = json.loads(
        PROFILE_PATH.read_text(
            encoding="utf-8"
        )
    )

    n = int(profile["ring_dimension"])
    q = int(profile["modulus"])

    psi = int(profile["psi"])
    omega = int(profile["omega"])

    psi_inverse = int(
        profile["psi_inverse"]
    )

    omega_inverse = int(
        profile["omega_inverse"]
    )

    n_inverse = int(
        profile["n_inverse"]
    )

    if n != 16:
        raise ValueError(
            f"Expected N=16, got N={n}"
        )

    if pow(psi, 2, q) != omega:
        raise ValueError(
            "omega != psi^2 mod q"
        )

    if (
        psi * psi_inverse
    ) % q != 1:
        raise ValueError(
            "psi inverse is invalid"
        )

    if (
        omega * omega_inverse
    ) % q != 1:
        raise ValueError(
            "omega inverse is invalid"
        )

    if (
        n * n_inverse
    ) % q != 1:
        raise ValueError(
            "N inverse is invalid"
        )

    if pow(psi, 2 * n, q) != 1:
        raise ValueError(
            "psi^(2N) != 1"
        )

    if pow(psi, n, q) != q - 1:
        raise ValueError(
            "psi does not have exact order 2N"
        )

    if pow(omega, n, q) != 1:
        raise ValueError(
            "omega^N != 1"
        )

    if pow(
        omega,
        n // 2,
        q,
    ) != q - 1:
        raise ValueError(
            "omega does not have exact order N"
        )

    # Deterministic vectors used by the future
    # SystemVerilog NTT controller testbench.
    vector_a = list(range(n))
    vector_b = list(range(n, 0, -1))

    forward_a, forward_a_trace = (
        forward_negacyclic_trace(
            vector_a,
            psi,
            omega,
            q,
        )
    )

    forward_b, forward_b_trace = (
        forward_negacyclic_trace(
            vector_b,
            psi,
            omega,
            q,
        )
    )

    pointwise_product = [
        (
            left_value *
            right_value
        ) % q
        for left_value, right_value
        in zip(forward_a, forward_b)
    ]

    convolution, inverse_product_trace = (
        inverse_negacyclic_trace(
            pointwise_product,
            psi_inverse,
            omega_inverse,
            n_inverse,
            q,
        )
    )

    expected_convolution = (
        schoolbook_negacyclic(
            vector_a,
            vector_b,
            q,
        )
    )

    if convolution != expected_convolution:
        raise AssertionError(
            "Deterministic transform convolution "
            "does not match schoolbook convolution"
        )

    round_trip_a, _ = inverse_negacyclic_trace(
        forward_a,
        psi_inverse,
        omega_inverse,
        n_inverse,
        q,
    )

    if round_trip_a != vector_a:
        raise AssertionError(
            "Deterministic NTT round trip failed"
        )

    rng = random.Random(RANDOM_SEED)

    for test_index in range(RANDOM_TESTS):
        left = [
            rng.randrange(q)
            for _ in range(n)
        ]

        right = [
            rng.randrange(q)
            for _ in range(n)
        ]

        left_ntt, _ = forward_negacyclic_trace(
            left,
            psi,
            omega,
            q,
        )

        recovered_left, _ = (
            inverse_negacyclic_trace(
                left_ntt,
                psi_inverse,
                omega_inverse,
                n_inverse,
                q,
            )
        )

        if recovered_left != left:
            raise AssertionError(
                "Round trip failed at randomized "
                f"test {test_index}"
            )

        right_ntt, _ = forward_negacyclic_trace(
            right,
            psi,
            omega,
            q,
        )

        product_ntt = [
            (
                left_value *
                right_value
            ) % q
            for left_value, right_value
            in zip(left_ntt, right_ntt)
        ]

        transform_product, _ = (
            inverse_negacyclic_trace(
                product_ntt,
                psi_inverse,
                omega_inverse,
                n_inverse,
                q,
            )
        )

        reference_product = (
            schoolbook_negacyclic(
                left,
                right,
                q,
            )
        )

        if transform_product != reference_product:
            raise AssertionError(
                "Convolution failed at randomized "
                f"test {test_index}"
            )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    butterflies_per_transform = (
        (n // 2) *
        int(math.log2(n))
    )

    artifact = {
        "description": (
            "N=16 negacyclic NTT golden data using "
            "an OpenFHE-derived modulus and root."
        ),
        "profile": profile,
        "convention": {
            "forward_twist": (
                "a[j] * psi^j mod q"
            ),
            "cyclic_transform": (
                "bit-reversed input, radix-2 DIT, "
                "natural-order output"
            ),
            "forward_root": (
                "omega = psi^2"
            ),
            "inverse_root": (
                "omega_inverse"
            ),
            "inverse_finish": (
                "multiply by N_inverse * "
                "psi_inverse^j mod q"
            ),
            "butterfly": {
                "t": (
                    "twiddle * b mod q"
                ),
                "out_a": (
                    "a + t mod q"
                ),
                "out_b": (
                    "a - t mod q"
                ),
            },
        },
        "butterflies_per_transform": (
            butterflies_per_transform
        ),
        "vector_a": {
            "input": vector_a,
            "forward": forward_a,
            "trace": forward_a_trace,
        },
        "vector_b": {
            "input": vector_b,
            "forward": forward_b,
            "trace": forward_b_trace,
        },
        "pointwise_product": (
            pointwise_product
        ),
        "inverse_product_trace": (
            inverse_product_trace
        ),
        "convolution": convolution,
        "schoolbook_convolution": (
            expected_convolution
        ),
        "random_validation": {
            "seed": RANDOM_SEED,
            "tests": RANDOM_TESTS,
            "round_trips_passed": (
                RANDOM_TESTS
            ),
            "convolutions_passed": (
                RANDOM_TESTS
            ),
        },
    }

    json_path = (
        OUTPUT_DIR /
        "openfhe_tower0_n16_golden.json"
    )

    json_path.write_text(
        json.dumps(
            artifact,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )

    write_mem(
        OUTPUT_DIR / "input_a.mem",
        vector_a,
    )

    write_mem(
        OUTPUT_DIR / "twisted_a.mem",
        forward_a_trace["twisted_input"],
    )

    write_trace_memories(
        "forward_a",
        forward_a_trace["cyclic_ntt"],
    )

    write_mem(
        OUTPUT_DIR / "forward_a.mem",
        forward_a,
    )

    write_mem(
        OUTPUT_DIR / "input_b.mem",
        vector_b,
    )

    write_mem(
        OUTPUT_DIR / "twisted_b.mem",
        forward_b_trace["twisted_input"],
    )

    write_trace_memories(
        "forward_b",
        forward_b_trace["cyclic_ntt"],
    )

    write_mem(
        OUTPUT_DIR / "forward_b.mem",
        forward_b,
    )

    write_mem(
        OUTPUT_DIR / "pointwise.mem",
        pointwise_product,
    )

    write_trace_memories(
        "inverse_product",
        inverse_product_trace[
            "cyclic_inverse_ntt"
        ],
    )

    write_mem(
        OUTPUT_DIR / "convolution.mem",
        convolution,
    )

    write_schedule(
        OUTPUT_DIR /
        "forward_schedule.csv",
        forward_a_trace["cyclic_ntt"],
    )

    write_schedule(
        OUTPUT_DIR /
        "inverse_schedule.csv",
        inverse_product_trace[
            "cyclic_inverse_ntt"
        ],
    )

    print(
        "PASS: OpenFHE-derived roots validated"
    )

    print(
        f"PASS: {RANDOM_TESTS} randomized "
        "NTT round trips"
    )

    print(
        f"PASS: {RANDOM_TESTS} randomized "
        "negacyclic convolutions"
    )

    print(
        f"N={n} q={q} "
        f"psi={psi} omega={omega}"
    )

    print(
        "butterflies_per_transform="
        f"{butterflies_per_transform}"
    )

    print(
        f"Wrote {json_path}"
    )

    print(
        "Wrote "
        f"{OUTPUT_DIR / 'forward_schedule.csv'}"
    )

    print(
        "Wrote "
        f"{OUTPUT_DIR / 'inverse_schedule.csv'}"
    )

    print(
        f"Wrote {OUTPUT_DIR}/*.mem"
    )


if __name__ == "__main__":
    main()
