#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

VECTOR_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
BOARD_HOST="${2:-xilinx@pynq}"
REMOTE_DIR="${3:-/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session}"
REMOTE_VECTOR_STAGE="$REMOTE_DIR/.vectors.installing"

required=(
  "$ROOT/openfhe_eval_domain_bridge/run_fpga_bv_keyreuse_multi_pair_session.py"
  "$ROOT/run_bv_keyreuse_multi_pair_session_board.sh"
  "$VECTOR_DIR/metadata.json"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required file: $path" >&2
    exit 1
  }
done

ssh "$BOARD_HOST" \
  "set -e
   mkdir -p '$REMOTE_DIR'
   rm -rf '$REMOTE_VECTOR_STAGE'
   mkdir -p '$REMOTE_VECTOR_STAGE'"

scp \
  "$ROOT/openfhe_eval_domain_bridge/run_fpga_bv_keyreuse_multi_pair_session.py" \
  "$ROOT/run_bv_keyreuse_multi_pair_session_board.sh" \
  "$BOARD_HOST:$REMOTE_DIR/"

tar \
  -C "$VECTOR_DIR" \
  -cf - \
  . \
| ssh "$BOARD_HOST" \
    "set -e
     tar -C '$REMOTE_VECTOR_STAGE' -xf -"

ssh "$BOARD_HOST" \
  "set -e
   test -f '$REMOTE_VECTOR_STAGE/metadata.json'
   rm -rf '$REMOTE_DIR/vectors'
   mv '$REMOTE_VECTOR_STAGE' '$REMOTE_DIR/vectors'
   test -f '$REMOTE_DIR/vectors/metadata.json'"

echo "PASS: uploaded CMA-arena runner and restored vectors"
