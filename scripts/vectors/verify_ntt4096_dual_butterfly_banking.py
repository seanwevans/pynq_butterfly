#!/usr/bin/env python3

from __future__ import annotations

N = 4096
LOG_N = 12
PAIRS_PER_STAGE = N // 4


def bank(address: int) -> int:
    """Two parity banks: even address bits -> bank bit 0, odd -> bit 1."""
    bank0 = 0
    bank1 = 0

    for bit in range(LOG_N):
        value = (address >> bit) & 1

        if bit & 1:
            bank1 ^= value
        else:
            bank0 ^= value

    return bank0 | (bank1 << 1)


def companion_bit(stage_bit: int) -> int:
    if stage_bit < LOG_N - 1:
        return stage_bit + 1

    return stage_bit - 1


def deposit_pair_index(
    packed_index: int,
    stage_bit: int,
    pair_bit: int,
) -> int:
    result = 0
    source_bit = 0

    for destination_bit in range(LOG_N):
        if destination_bit in (stage_bit, pair_bit):
            continue

        result |= (
            ((packed_index >> source_bit) & 1)
            << destination_bit
        )

        source_bit += 1

    assert source_bit == LOG_N - 2

    return result


def addresses_for_cycle(
    stage_bit: int,
    packed_index: int,
) -> tuple[int, int, int, int]:
    pair_bit = companion_bit(stage_bit)

    base = deposit_pair_index(
        packed_index,
        stage_bit,
        pair_bit,
    )

    first_a = base
    first_b = base | (1 << stage_bit)

    second_a = base | (1 << pair_bit)
    second_b = second_a | (1 << stage_bit)

    return first_a, first_b, second_a, second_b


def verify_stage(stage_bit: int) -> None:
    seen_addresses: set[int] = set()
    seen_butterflies: set[tuple[int, int]] = set()

    for packed_index in range(PAIRS_PER_STAGE):
        addresses = addresses_for_cycle(
            stage_bit,
            packed_index,
        )

        banks = tuple(
            bank(address)
            for address in addresses
        )

        if len(set(addresses)) != 4:
            raise AssertionError(
                f"stage {stage_bit}: duplicate address in {addresses}"
            )

        if len(set(banks)) != 4:
            raise AssertionError(
                f"stage {stage_bit}: bank conflict "
                f"addresses={addresses}, banks={banks}"
            )

        first = (
            min(addresses[0], addresses[1]),
            max(addresses[0], addresses[1]),
        )

        second = (
            min(addresses[2], addresses[3]),
            max(addresses[2], addresses[3]),
        )

        for butterfly in (first, second):
            if butterfly in seen_butterflies:
                raise AssertionError(
                    f"stage {stage_bit}: duplicate butterfly {butterfly}"
                )

            seen_butterflies.add(butterfly)

        for address in addresses:
            if address in seen_addresses:
                raise AssertionError(
                    f"stage {stage_bit}: duplicate address {address}"
                )

            seen_addresses.add(address)

    expected_butterflies = {
        (
            address,
            address | (1 << stage_bit),
        )
        for address in range(N)
        if ((address >> stage_bit) & 1) == 0
    }

    if seen_butterflies != expected_butterflies:
        missing = expected_butterflies - seen_butterflies
        extra = seen_butterflies - expected_butterflies

        raise AssertionError(
            f"stage {stage_bit}: coverage failure; "
            f"missing={len(missing)}, extra={len(extra)}"
        )

    if seen_addresses != set(range(N)):
        raise AssertionError(
            f"stage {stage_bit}: coefficient coverage failure"
        )


def main() -> None:
    for stage_bit in range(LOG_N):
        verify_stage(stage_bit)

        print(
            f"PASS: stage bit {stage_bit:2d} "
            f"uses {PAIRS_PER_STAGE} conflict-free paired cycles"
        )

    transform_cycles = LOG_N * PAIRS_PER_STAGE

    print(
        "PASS: fixed four-bank parity mapping covers all "
        "4096 coefficients once per stage"
    )

    print(
        "PASS: the same paired schedule supports ascending DIT "
        "and descending DIF stage order"
    )

    print(
        f"Paired butterfly cycles per stage: {PAIRS_PER_STAGE}"
    )

    print(
        f"Paired butterfly cycles per transform: {transform_cycles}"
    )

    print(
        f"Single-butterfly cycles per transform: {2 * transform_cycles}"
    )

    print(
        "Structural butterfly issue reduction: 2.000x"
    )


if __name__ == "__main__":
    main()
