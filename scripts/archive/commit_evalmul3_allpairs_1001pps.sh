#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

cd "$ROOT"

BRANCH="evalmul3-all-pair-frame"
TAG="pynq-z2-evalmul3-allpairs-1001pps"
MESSAGE="perf: exceed 1000 exact EvalMultNoRelin per second at batch 64"

current_branch="$(git branch --show-current)"

if [[ "$current_branch" != "$BRANCH" ]]; then
  echo "error: expected branch $BRANCH, found $current_branch" >&2
  exit 1
fi

paths=(
  README.md
  docs/history/readme-evalmul3-allpairs.md
  docs/results/results-evalmul3-allpairs-1001pps.md
  scripts/archive/begin_evalmul3_allpairs_branch.sh
  scripts/sim/run_evalmul3_allpairs_checkpoint.sh
  scripts/vivado/build_evalmul3_allpairs_dma150_overlay.sh
  scripts/board/install/install_evalmul3_allpairs_board.sh
  scripts/board/run/run_evalmul3_allpairs_board.sh
  openfhe_eval_domain_bridge/run_fpga_evalmul3_allpairs.py
  rtl/evalmul3_all_tower_axis_core.sv
  rtl/evalmul3_two_tower_axis_dma_wrapper.v
  scripts/sim/run_evalmul3_all_tower_axis_sim.sh
  scripts/vivado/build_evalmul3_allpairs_dma150_overlay.tcl
  tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv
  tests/rtl/tb_evalmul3_all_tower_axis_core.sv
  deploy/evalmul3_allpairs_dma150
)

for path in "${paths[@]}"; do
  [[ -e "$path" ]] || {
    echo "error: missing release path: $path" >&2
    exit 1
  }
done

# Normalize only generated Vivado text reports.
python3 - <<'PY'
from pathlib import Path

root = Path("deploy/evalmul3_allpairs_dma150")

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

git add -- "${paths[@]}"
git diff --cached --check

echo
git status --short

echo
git diff --cached --stat

if git diff --cached --quiet; then
  echo "error: nothing staged" >&2
  exit 1
fi

git commit -m "$MESSAGE"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag already exists: $TAG" >&2
  exit 1
fi

git tag -a \
  "$TAG" \
  -m "Exact 12-tower OpenFHE EvalMultNoRelin at 1001.51/s using one batch-64 EV12 transaction"

echo
echo "Committed and tagged:"
echo "  branch: $BRANCH"
echo "  tag:    $TAG"

if [[ "${1:-}" == "--push" ]]; then
  git push -u origin "$BRANCH"
  git push origin "$TAG"
  echo "Pushed branch and tag."
else
  echo
  echo "Not pushed. To publish:"
  echo "  git push -u origin $BRANCH"
  echo "  git push origin $TAG"
fi
