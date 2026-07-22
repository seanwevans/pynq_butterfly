#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

WORK_DIR="${EVALMUL3_DMA_WORK:-/mnt/f/v/evalmul3_dma_overlay}"
DEPLOY_DIR="$ROOT/deploy/evalmul3_two_tower_dma"
SUMMARY="$WORK_DIR/build_summary.txt"

PASS_MARKER='PASS: fused evaluation-domain DMA overlay routed at 100 MHz'

[[ -f "$SUMMARY" ]] || {
  echo "error: missing build summary: $SUMMARY" >&2
  exit 1
}

if ! tr -d '\r' <"$SUMMARY" | grep -Fxq "$PASS_MARKER"; then
  echo "error: routed overlay PASS marker not found" >&2
  tr -d '\r' <"$SUMMARY" >&2
  exit 1
fi

required=(
  "$DEPLOY_DIR/evalmul3_two_tower_dma.bit"
  "$DEPLOY_DIR/evalmul3_two_tower_dma.hwh"
  "$ROOT/openfhe_eval_domain_bridge/run_fpga_evalmul3.py"
  "$WORK_DIR/routed_timing_summary.rpt"
  "$WORK_DIR/routed_utilization.rpt"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required artifact: $path" >&2
    exit 1
  }
done

mkdir -p "$DEPLOY_DIR"

install -m 0755 \
  "$ROOT/openfhe_eval_domain_bridge/run_fpga_evalmul3.py" \
  "$DEPLOY_DIR/run_fpga_evalmul3.py"

cp -f \
  "$WORK_DIR/routed_timing_summary.rpt" \
  "$DEPLOY_DIR/"

cp -f \
  "$WORK_DIR/routed_utilization.rpt" \
  "$DEPLOY_DIR/"

tr -d '\r' <"$SUMMARY" \
  >"$DEPLOY_DIR/build_summary.txt"

echo "PASS: finalized existing fused evaluation-domain DMA overlay"
echo
echo "Deploy:"
for artifact in \
  "$DEPLOY_DIR/evalmul3_two_tower_dma.bit" \
  "$DEPLOY_DIR/evalmul3_two_tower_dma.hwh" \
  "$DEPLOY_DIR/run_fpga_evalmul3.py" \
  "$DEPLOY_DIR/build_summary.txt" \
  "$DEPLOY_DIR/routed_timing_summary.rpt" \
  "$DEPLOY_DIR/routed_utilization.rpt"; do
  echo "  PASS $artifact"
done
