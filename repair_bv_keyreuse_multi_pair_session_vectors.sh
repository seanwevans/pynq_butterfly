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

[[ -f "$VECTOR_DIR/metadata.json" ]] || {
  echo "error: missing local vector metadata: $VECTOR_DIR/metadata.json" >&2
  exit 1
}

ssh "$BOARD_HOST" \
  "set -e
   mkdir -p '$REMOTE_DIR'
   rm -rf '$REMOTE_VECTOR_STAGE'
   mkdir -p '$REMOTE_VECTOR_STAGE'"

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
   mv '$REMOTE_VECTOR_STAGE' '$REMOTE_DIR/vectors'"

echo "PASS: repaired remote vector installation"
