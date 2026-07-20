#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


PROFILE_FILES = (
    "profile.json",
    "twist_factors.mem",
    "forward_twiddles.mem",
    "inverse_twiddles.mem",
    "inverse_scale_factors.mem",
)

PRODUCT_FILES = (
    "tower0/dma_input.bin",
    "tower0/openfhe_expected.bin",
    "tower1/dma_input.bin",
    "tower1/openfhe_expected.bin",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def combined_product_hash(product_root: Path) -> str:
    digest = hashlib.sha256()
    for relative in PRODUCT_FILES:
        path = product_root / relative
        if not path.is_file():
            raise FileNotFoundError(path)
        digest.update(relative.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def profile_hashes(product_root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for profile_index in (0, 1):
        profile_root = product_root / f"profile{profile_index}"
        for name in PROFILE_FILES:
            path = profile_root / name
            if not path.is_file():
                raise FileNotFoundError(path)
            result[f"profile{profile_index}/{name}"] = sha256_file(path)
    return result


def run_pair_generator(
    pair_generator: Path,
    bridge: Path,
    output: Path,
    seed0: int,
    seed1: int,
) -> None:
    command = [
        sys.executable,
        str(pair_generator),
        "--bridge",
        str(bridge),
        "--output",
        str(output),
        "--seed0",
        str(seed0),
        "--seed1",
        str(seed1),
    ]
    print("\nRUN:", " ".join(command), "\n")
    subprocess.run(command, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Generate distinct two-tower OpenFHE products for an FPGA "
            "batch-count sweep."
        )
    )
    parser.add_argument(
        "--pair-generator",
        type=Path,
        required=True,
        help="Existing prepare_dual_butterfly_batch2_openfhe_vectors.py",
    )
    parser.add_argument(
        "--bridge",
        type=Path,
        required=True,
        help="Compiled two-tower OpenFHE bridge executable",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--base-seed", type=int, default=202947043366)
    parser.add_argument("--products", type=int, default=16)
    args = parser.parse_args()

    pair_generator = args.pair_generator.resolve()
    bridge = args.bridge.resolve()
    output = args.output.resolve()

    if not pair_generator.is_file():
        raise FileNotFoundError(pair_generator)
    if not bridge.is_file():
        raise FileNotFoundError(bridge)
    if args.products <= 0:
        raise ValueError("--products must be positive")
    if args.products % 2 != 0:
        raise ValueError(
            "--products must be even because the existing generator "
            "produces products in pairs"
        )

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, object]] = []
    seen_hashes: set[str] = set()
    reference_profiles: dict[str, str] | None = None

    with tempfile.TemporaryDirectory(prefix="pynq_batch_sweep_") as temp_name:
        temporary_root = Path(temp_name)

        for pair_index in range(args.products // 2):
            seed0 = args.base_seed + 2 * pair_index
            seed1 = seed0 + 1
            pair_output = temporary_root / f"pair{pair_index}"

            run_pair_generator(
                pair_generator=pair_generator,
                bridge=bridge,
                output=pair_output,
                seed0=seed0,
                seed1=seed1,
            )

            for local_index, seed in enumerate((seed0, seed1)):
                product_index = 2 * pair_index + local_index
                source = pair_output / f"product{local_index}"
                destination = output / f"product{product_index}"

                if not source.is_dir():
                    raise FileNotFoundError(source)

                shutil.copytree(source, destination)

                current_profiles = profile_hashes(destination)
                if reference_profiles is None:
                    reference_profiles = current_profiles
                elif current_profiles != reference_profiles:
                    raise RuntimeError(
                        f"Runtime profile mismatch at product {product_index}"
                    )

                product_hash = combined_product_hash(destination)
                if product_hash in seen_hashes:
                    raise RuntimeError(
                        f"Duplicate generated product at index {product_index}"
                    )
                seen_hashes.add(product_hash)

                records.append(
                    {
                        "index": product_index,
                        "seed": seed,
                        "sha256": product_hash,
                        "directory": f"product{product_index}",
                    }
                )

                print(
                    f"PASS: product {product_index:02d} seed={seed} "
                    f"sha256={product_hash[:16]}..."
                )

    manifest = {
        "format": "pynq-openfhe-two-tower-batch-sweep-v1",
        "base_seed": args.base_seed,
        "product_count": args.products,
        "products": records,
        "profile_hashes": reference_profiles,
    }

    manifest_path = output / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(f"\nPASS: generated {args.products} distinct two-tower OpenFHE products")
    print("PASS: q0/q1 runtime profiles are identical across the full sweep")
    print(f"Manifest: {manifest_path}")
    print(f"Output directory: {output}")


if __name__ == "__main__":
    main()
