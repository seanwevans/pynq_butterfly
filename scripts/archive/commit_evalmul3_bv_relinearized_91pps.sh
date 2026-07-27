#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BRANCH="${EXPECTED_BRANCH:-evalmul-relinearization}"
TAG="${TAG:-pynq-z2-bv-relinearized-91pps}"
MESSAGE="${MESSAGE:-feat: run exact fused OpenFHE BV relinearization on PYNQ-Z2}"

current_branch="$(git branch --show-current)"

if [[ "$current_branch" != "$EXPECTED_BRANCH" ]]; then
  echo \
    "error: expected branch '$EXPECTED_BRANCH', got '$current_branch'" \
    >&2
  exit 1
fi

paths=(
  README_EVALMUL3_BV_RELINEARIZED_RELEASE.md
  RESULTS_EVALMUL3_BV_RELINEARIZED_91PPS.md
  NEXT_EVAL_KEY_REUSE_ARCHITECTURE.md
  openfhe_eval_domain_bridge/openfhe_relinearization_probe.cpp
  openfhe_eval_domain_bridge/prepare_evalmul3_bv_relinearized_vectors.py
  openfhe_eval_domain_bridge/run_fpga_evalmul3_bv_relinearized.py
  rtl/evalmul3_two_tower_axis_core.sv
  rtl/bv_keyswitch_mac_two_tower_axis_core.sv
  rtl/evalmul3_bv_relinearize_two_tower_axis_core.sv
  rtl/evalmul3_bv_relinearized_axis_dma_wrapper.v
  tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv
  tests/rtl/tb_evalmul3_bv_relinearize_two_tower_axis_core.sv
  scripts/sim/run_evalmul3_bv_relinearized_openfhe_sim.sh
  scripts/vivado/build_evalmul3_bv_relinearized_dma150_overlay.tcl
  scripts/sim/run_evalmul3_bv_relinearized_checkpoint.sh
  scripts/vivado/build_evalmul3_bv_relinearized_dma150_overlay.sh
  scripts/board/install/install_evalmul3_bv_relinearized_board.sh
  scripts/board/run/run_evalmul3_bv_relinearized_board.sh
  deploy/evalmul3_bv_relinearized_dma150
)

for path in "${paths[@]}"; do
  [[ -e "$path" ]] || {
    echo "error: missing checkpoint path: $path" >&2
    exit 1
  }
done

git add -- "${paths[@]}"

if git diff --cached --quiet; then
  echo "error: checkpoint produced no staged changes" >&2
  exit 1
fi

echo "Staged checkpoint:"
git diff --cached --stat

git commit -m "$MESSAGE"
git tag -a "$TAG" -m "$MESSAGE"

if [[ "${1:-}" == "--push" ]]; then
  git push origin "$current_branch"
  git push origin "$TAG"
fi

echo
echo "PASS: committed exact fused BV relinearization checkpoint"
echo "commit=$(git rev-parse HEAD)"
echo "tag=$TAG"
