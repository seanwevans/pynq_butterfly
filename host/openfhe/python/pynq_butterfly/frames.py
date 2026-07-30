"""Frame packing primitives shared by all FPGA runners."""
from __future__ import annotations

from collections.abc import Iterable

RING_DIMENSION = 4096
WORD_MASK = (1 << 32) - 1


def pack_lanes(lane0: int, lane1: int) -> int:
    """Pack two unsigned 32-bit lanes into one little-lane-order word."""
    if not 0 <= lane0 <= WORD_MASK or not 0 <= lane1 <= WORD_MASK:
        raise ValueError("frame lanes must be unsigned 32-bit values")
    return lane0 | (lane1 << 32)


def split_lanes(words: Iterable[int]) -> tuple[list[int], list[int]]:
    """Decode packed words into lane-zero and lane-one lists."""
    lane0: list[int] = []
    lane1: list[int] = []
    for word in words:
        if not 0 <= word <= (1 << 64) - 1:
            raise ValueError("packed frame words must be unsigned 64-bit values")
        lane0.append(word & WORD_MASK)
        lane1.append((word >> 32) & WORD_MASK)
    return lane0, lane1
