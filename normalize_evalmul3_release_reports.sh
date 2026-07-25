#!/usr/bin/env bash
set -euo pipefail

cd "$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

python3 - <<'PY'
from pathlib import Path

root = Path("deploy/evalmul3_two_tower_dma")

for path in sorted(root.rglob("*")):
    if not path.is_file() or path.suffix.lower() not in {".rpt", ".txt"}:
        continue

    text = path.read_bytes().decode("utf-8", errors="strict")
    lines = [line.rstrip(" \t\r") for line in text.splitlines()]

    while lines and lines[-1] == "":
        lines.pop()

    path.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    print(f"normalized: {path}")
PY

git add -- deploy/evalmul3_two_tower_dma
git diff --cached --check

echo
echo "PASS: Vivado reports have Git-clean whitespace"
