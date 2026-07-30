#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
  pwd
)"

VECTOR_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
BOARD_HOST="${2:-xilinx@pynq}"
REMOTE_DIR="${3:-/home/xilinx/jupyter_notebooks/evalmul3_bv_relinearized}"

DEPLOY_DIR="$ROOT/deploy/evalmul3_bv_relinearized_dma150"
RUNNER="$ROOT/openfhe_eval_domain_bridge/run_fpga_evalmul3_bv_relinearized.py"

required=(
  "$DEPLOY_DIR/evalmul3_bv_relinearized_dma150.bit"
  "$DEPLOY_DIR/evalmul3_bv_relinearized_dma150.hwh"
  "$RUNNER"
  "$ROOT/scripts/board/run/run_evalmul3_bv_relinearized_board.sh"
  "$VECTOR_DIR/metadata.json"
  "$VECTOR_DIR/input_a0_q_eval/poly.json"
  "$VECTOR_DIR/digits/digit000/poly.json"
  "$VECTOR_DIR/eval_key_a/digit000/poly.json"
  "$VECTOR_DIR/relinearized_c0_q/poly.json"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required file: $path" >&2
    exit 1
  }
done

ssh "$BOARD_HOST" \
  "mkdir -p '$REMOTE_DIR' && rm -rf '$REMOTE_DIR/vectors' '$REMOTE_DIR/results'"

scp \
  "$DEPLOY_DIR/evalmul3_bv_relinearized_dma150.bit" \
  "$DEPLOY_DIR/evalmul3_bv_relinearized_dma150.hwh" \
  "$RUNNER" \
  "$ROOT/scripts/board/run/run_evalmul3_bv_relinearized_board.sh" \
  "$BOARD_HOST:$REMOTE_DIR/"

scp -r \
  "$VECTOR_DIR" \
  "$BOARD_HOST:$REMOTE_DIR/vectors"

echo
echo "Installed:"
echo "  $BOARD_HOST:$REMOTE_DIR"
echo
echo "Run:"
echo "  ssh $BOARD_HOST"
echo "  $REMOTE_DIR/run_evalmul3_bv_relinearized_board.sh $REMOTE_DIR 8 5"
