#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

VECTOR_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
BOARD_HOST="${2:-xilinx@pynq}"
REMOTE_DIR="${3:-/home/xilinx/jupyter_notebooks/bv_keyreuse_multi_pair_session}"

DEPLOY_DIR="$ROOT/deploy/bv_keyreuse_multi_pair_session_dma150"
RUNNER="$ROOT/openfhe_eval_domain_bridge/run_fpga_bv_keyreuse_multi_pair_session.py"
REMOTE_VECTOR_STAGE="$REMOTE_DIR/.vectors.installing"

required=(
  "$DEPLOY_DIR/evalmul3_bv_keyreuse_multi_pair_session_dma150.bit"
  "$DEPLOY_DIR/evalmul3_bv_keyreuse_multi_pair_session_dma150.hwh"
  "$RUNNER"
  "$ROOT/run_bv_keyreuse_multi_pair_session_board.sh"
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

# Never touch results here. They are commonly root-owned because the board
# benchmark runs under sudo -i.
ssh "$BOARD_HOST" \
  "set -e
   mkdir -p '$REMOTE_DIR'
   rm -rf '$REMOTE_VECTOR_STAGE'
   mkdir -p '$REMOTE_VECTOR_STAGE'"

scp \
  "$DEPLOY_DIR/evalmul3_bv_keyreuse_multi_pair_session_dma150.bit" \
  "$DEPLOY_DIR/evalmul3_bv_keyreuse_multi_pair_session_dma150.hwh" \
  "$RUNNER" \
  "$ROOT/run_bv_keyreuse_multi_pair_session_board.sh" \
  "$BOARD_HOST:$REMOTE_DIR/"

# Stream vector contents without the scp '/.' incompatibility.
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

echo
echo "Installed:"
echo "  $BOARD_HOST:$REMOTE_DIR"
echo
echo "Existing benchmark results were preserved."
echo
echo "Run B64 after a fresh board reboot:"
echo "  ssh $BOARD_HOST"
echo "  sudo -i"
echo "  REMOTE='$REMOTE_DIR'"
echo '  "$REMOTE/run_bv_keyreuse_multi_pair_session_board.sh" "$REMOTE" 64 5 | tee "$REMOTE/results/batch_64_arena.log"'
