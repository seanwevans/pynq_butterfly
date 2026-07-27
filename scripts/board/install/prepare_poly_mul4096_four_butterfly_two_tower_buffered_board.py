#!/usr/bin/env python3
from pathlib import Path

repo = Path(__file__).resolve().parents[3]
source = repo / "scripts" / "board" / "run" / "test_poly_mul4096_four_butterfly_two_tower_batch_dma.py"
destination = repo / "scripts" / "board" / "run" / "test_poly_mul4096_four_butterfly_two_tower_buffered_dma.py"

if not source.is_file():
    raise SystemExit(f"missing source benchmark: {source}")

text = source.read_text(encoding="utf-8")

old_constants = """DIRECT_CYCLES_PER_PRODUCT = (
    INPUT_WORDS_PER_PRODUCT
    + CORE_CYCLES
    + OUTPUT_STATE_CYCLES_PER_PRODUCT
)
"""

new_constants = """BUFFERED_STEADY_CYCLES_PER_PRODUCT = 23_993
BUFFERED_FIXED_CYCLES = (
    2
    + INPUT_WORDS_PER_PRODUCT
    + OUTPUT_STATE_CYCLES_PER_PRODUCT
)
"""

old_ideal = """                ideal_total_cycles = (
                    2 + batch_size * DIRECT_CYCLES_PER_PRODUCT
                )
"""

new_ideal = """                ideal_total_cycles = (
                    BUFFERED_FIXED_CYCLES
                    + batch_size * BUFFERED_STEADY_CYCLES_PER_PRODUCT
                )
"""

replacements = [
    (old_constants, new_constants),
    (
        '"Benchmark batched four-butterfly two-tower N=4096 "\n'
        '            "multiplication on PYNQ-Z2."',
        '"Benchmark four-wide buffered four-butterfly two-tower "\n'
        '            "N=4096 multiplication on PYNQ-Z2."',
    ),
    (old_ideal, new_ideal),
    (
        'print("Batched measurements")',
        'print("Four-wide buffered measurements")\n'
        '        print("Steady hardware cadence: 23993 cycles/product")',
    ),
    (
        'print("PASS: every MUL1/MULB result matches OpenFHE")',
        'print("PASS: every buffered MUL1/MULB result matches OpenFHE")',
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"expected exactly one benchmark patch target; found {count}: {old[:80]!r}"
        )
    text = text.replace(old, new, 1)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
print(f"generated {destination}")
