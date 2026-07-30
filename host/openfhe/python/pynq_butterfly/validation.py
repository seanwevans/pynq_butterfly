"""Reusable result validation."""
from __future__ import annotations
from collections.abc import Sequence


def require_equal(actual: Sequence[int], expected: Sequence[int], label: str) -> None:
    if len(actual) != len(expected):
        raise ValueError(f"{label}: length {len(actual)} != {len(expected)}")
    for index, (got, want) in enumerate(zip(actual, expected)):
        if int(got) != int(want):
            raise ValueError(f"{label}[{index}]: got {int(got)}, expected {int(want)}")
