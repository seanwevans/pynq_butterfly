#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
  pwd
)"

VECTOR_DIR="${1:?usage: $0 VECTOR_DIRECTORY [BOARD_HOST] [REMOTE_DIR]}"
BOARD_HOST="${2:-xilinx@pynq}"
REMOTE_DIR="${3:-/home/xilinx/jupyter_notebooks/evalmul3}"

DEPLOY_DIR="$ROOT/deploy/evalmul3_two_tower_dma"
RUNNER="$ROOT/openfhe_eval_domain_bridge/run_fpga_evalmul3.py"

required=(
  "$DEPLOY_DIR/evalmul3_two_tower_dma.bit"
  "$DEPLOY_DIR/evalmul3_two_tower_dma.hwh"
  "$RUNNER"
  "$ROOT/scripts/board/run/run_evalmul3_board_sweep.sh"
  "$VECTOR_DIR/metadata.json"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required file: $path" >&2
    exit 1
  }
done

ssh "$BOARD_HOST" \
  "mkdir -p '$REMOTE_DIR' && rm -rf '$REMOTE_DIR/vectors' '$REMOTE_DIR/results_sweep'"

scp \
  "$DEPLOY_DIR/evalmul3_two_tower_dma.bit" \
  "$DEPLOY_DIR/evalmul3_two_tower_dma.hwh" \
  "$RUNNER" \
  "$ROOT/scripts/board/run/run_evalmul3_board_sweep.sh" \
  "$BOARD_HOST:$REMOTE_DIR/"

scp -r \
  "$VECTOR_DIR" \
  "$BOARD_HOST:$REMOTE_DIR/vectors"

echo
echo "Installed sweep:"
echo "  $BOARD_HOST:$REMOTE_DIR"
