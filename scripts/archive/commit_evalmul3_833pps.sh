#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

cd "$ROOT"

BRANCH="eval-domain-ciphertext-fused"
TAG="pynq-z2-evalmul3-833pps"
MESSAGE="feat: accelerate OpenFHE EvalMultNoRelin in evaluation domain"

current_branch="$(git branch --show-current)"

if [[ "$current_branch" != "$BRANCH" ]]; then
  echo "error: expected branch $BRANCH, found $current_branch" >&2
  exit 1
fi

rm -f \
  rtl/evalmul3_two_tower_axis_dma_wrapper.sv

paths=(
  RESULTS_EVALMUL3_833PPS.md
  README_EVAL_DOMAIN_FUSED_NEXT.md
  README_EVALMUL3_OOC_PHYSICAL.md
  README_EVALMUL3_DMA_OVERLAY.md
  scripts/archive/begin_eval_domain_fused_branch.sh
  scripts/sim/run_eval_domain_fused_checkpoint.sh
  scripts/vivado/build_evalmul3_ooc.sh
  scripts/vivado/build_evalmul3_dma_overlay.sh
  scripts/archive/finalize_evalmul3_dma_overlay.sh
  scripts/board/install/install_evalmul3_board.sh
  scripts/board/run/run_evalmul3_board.sh
  openfhe_eval_domain_bridge/.gitignore
  openfhe_eval_domain_bridge/CMakeLists.txt
  openfhe_eval_domain_bridge/build.sh
  openfhe_eval_domain_bridge/openfhe_eval_domain_bridge.cpp
  openfhe_eval_domain_bridge/run_fpga_evalmul3.py
  rtl/evalmul3_two_tower_axis_core.sv
  rtl/evalmul3_two_tower_axis_dma_wrapper.v
  scripts/sim/run_evalmul3_two_tower_axis_sim.sh
  scripts/vivado/build_evalmul3_ooc.tcl
  scripts/vivado/build_evalmul3_dma_overlay.tcl
  tests/rtl/tb_evalmul3_two_tower_axis_core.sv
  deploy/evalmul3_two_tower_dma
)

for path in "${paths[@]}"; do
  [[ -e "$path" ]] || {
    echo "error: missing release path: $path" >&2
    exit 1
  }
done

# Vivado reports contain CRLF, padded table rows, and trailing blank lines.
# Normalize only generated text artifacts before staging:
#   - remove CRLF carriage returns;
#   - remove trailing spaces and tabs from every line;
#   - remove blank lines at EOF;
#   - leave exactly one final newline.
python3 - <<'PY'
from pathlib import Path

root = Path("deploy/evalmul3_two_tower_dma")

for path in sorted(root.rglob("*")):
    if not path.is_file() or path.suffix.lower() not in {".rpt", ".txt"}:
        continue

    raw = path.read_bytes()
    text = raw.decode("utf-8", errors="strict")
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
  -m "Exact 12-tower OpenFHE EvalMultNoRelin at 832.95 compute ciphertexts/s"

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
