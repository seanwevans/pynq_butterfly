#!/usr/bin/env python3
"""Generate every reproducible RTL fixture committed to the repository."""

from __future__ import annotations

import argparse
import filecmp
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
VECTOR_SOURCE = REPOSITORY_ROOT / "openfhe_two_tower_runtime_bridge" / "vectors"


@dataclass(frozen=True)
class Fixture:
    destination: Path
    generator: Path
    input_option: str


FIXTURES = (
    Fixture(
        Path("rtl/generated_dual_butterfly"),
        Path("scripts/vectors/prepare_dual_butterfly_ntt_vectors.py"),
        "--vectors",
    ),
    Fixture(
        Path("rtl/generated_dual_lane"),
        Path("scripts/vectors/prepare_dual_lane_mem.py"),
        "--vectors",
    ),
    Fixture(
        Path("rtl/generated_dual_butterfly_poly"),
        Path("scripts/vectors/prepare_dual_butterfly_poly_mul_vectors.py"),
        "--vectors",
    ),
    Fixture(
        Path("rtl/generated_dual_butterfly_axis"),
        Path("scripts/vectors/prepare_dual_butterfly_two_tower_axis_vectors.py"),
        "--vectors",
    ),
    Fixture(
        Path("rtl/generated_four_butterfly_ntt"),
        Path("scripts/vectors/prepare_ntt4096_four_butterfly_vectors.py"),
        "--input",
    ),
)


def differing_files(expected: Path, generated: Path) -> list[str]:
    """Return relative paths that are missing, extra, or byte-different."""
    expected_files = {
        path.relative_to(expected)
        for path in expected.rglob("*")
        if path.is_file()
    }
    generated_files = {
        path.relative_to(generated)
        for path in generated.rglob("*")
        if path.is_file()
    }
    differences = expected_files ^ generated_files
    differences.update(
        relative
        for relative in expected_files & generated_files
        if not filecmp.cmp(
            expected / relative,
            generated / relative,
            shallow=False,
        )
    )
    return sorted(str(path) for path in differences)


def generate_into(staging_root: Path) -> None:
    for fixture in FIXTURES:
        output = staging_root / fixture.destination
        output.mkdir(parents=True)
        subprocess.run(
            [
                sys.executable,
                str(REPOSITORY_ROOT / fixture.generator),
                fixture.input_option,
                str(VECTOR_SOURCE),
                "--output",
                str(output),
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
        )


def check(staging_root: Path) -> int:
    stale = False
    for fixture in FIXTURES:
        destination = REPOSITORY_ROOT / fixture.destination
        differences = differing_files(
            destination,
            staging_root / fixture.destination,
        )
        if differences:
            stale = True
            print(f"STALE: {fixture.destination}", file=sys.stderr)
            for relative in differences:
                print(f"  {relative}", file=sys.stderr)

    if stale:
        print(
            "Fixture check failed; run scripts/generate_fixtures.py and commit "
            "the results.",
            file=sys.stderr,
        )
        return 1

    print("PASS: committed RTL fixtures are current")
    return 0


def install(staging_root: Path) -> None:
    for fixture in FIXTURES:
        source = staging_root / fixture.destination
        destination = REPOSITORY_ROOT / fixture.destination
        shutil.rmtree(destination, ignore_errors=True)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, destination)
        print(f"Updated {fixture.destination}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Regenerate the deterministic RTL fixtures from the committed "
            "OpenFHE two-tower vectors."
        )
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify fixtures in a temporary directory without rewriting them",
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="pynq-fixtures-") as temporary:
        staging_root = Path(temporary)
        generate_into(staging_root)
        if args.check:
            return check(staging_root)
        install(staging_root)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
