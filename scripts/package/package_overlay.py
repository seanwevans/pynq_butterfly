#!/usr/bin/env python3
"""Assemble a board overlay without modifying its checked-in metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package(metadata_path: Path, source: Path, output_root: Path) -> Path:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    overlay = metadata["overlay"]
    if not isinstance(overlay, str) or not overlay or Path(overlay).name != overlay:
        raise ValueError("metadata 'overlay' must be one directory name")

    payload = metadata.get("payload", [])
    if not isinstance(payload, list) or not all(isinstance(item, str) for item in payload):
        raise ValueError("metadata 'payload' must be a list of file names")

    destination = output_root / overlay
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)

    inventory = []
    for relative_name in payload:
        relative = Path(relative_name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"payload path must be relative to its overlay: {relative_name}")
        source_path = source / relative
        if not source_path.is_file():
            raise FileNotFoundError(f"missing payload file: {source_path}")
        destination_path = destination / relative
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination_path)
        inventory.append(
            {
                "path": relative.as_posix(),
                "bytes": destination_path.stat().st_size,
                "sha256": sha256(destination_path),
            }
        )

    generated_at = datetime.now(timezone.utc).isoformat()
    packaged_manifest = {**metadata, "generated_at": generated_at, "inventory": inventory}
    (destination / "manifest.json").write_text(
        json.dumps(packaged_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (destination / "package_summary.txt").write_text(
        f"overlay={overlay}\ngenerated_at={generated_at}\nfiles={len(inventory)}\n"
        f"bytes={sum(item['bytes'] for item in inventory)}\n",
        encoding="utf-8",
    )
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", type=Path, help="checked-in overlay metadata JSON")
    parser.add_argument("--source", type=Path, help="payload staging directory")
    parser.add_argument("--output-root", type=Path, default=Path("artifacts/deploy"))
    args = parser.parse_args()
    source = args.source if args.source is not None else args.metadata.parent
    print(package(args.metadata, source, args.output_root))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
