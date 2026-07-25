#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

TOWER_COUNT="${1:?usage: $0 TOWER_COUNT CIPHERTEXT_COUNT}"
CIPHERTEXT_COUNT="${2:?usage: $0 TOWER_COUNT CIPHERTEXT_COUNT}"

PYNQ_SSH="${PYNQ_SSH:-xilinx@pynq}"
REMOTE_DIR="${PYNQ_REMOTE_DIR:-/home/xilinx/jupyter_notebooks/p4ttbo_ciphertext}"

VECTOR_DIR="$ROOT/vectors/t${TOWER_COUNT}_c${CIPHERTEXT_COUNT}"
RESULT_DIR="$ROOT/results/t${TOWER_COUNT}_c${CIPHERTEXT_COUNT}"
BRIDGE="$ROOT/build/openfhe_ciphertext_bridge"

[[ -x "$BRIDGE" ]] || {
  echo "error: missing bridge executable: $BRIDGE" >&2
  echo "run ./build.sh first" >&2
  exit 1
}

[[ -f "$VECTOR_DIR/metadata.json" ]] || {
  echo "error: missing vector set: $VECTOR_DIR" >&2
  exit 1
}

temporary="${RESULT_DIR}.incoming.$$"
printf -v remote_results_q '%q' "$REMOTE_DIR/results"

rm -rf "$temporary"
mkdir -p "$temporary"

echo "Retrieving existing FPGA results from:"
echo "  $PYNQ_SSH:$REMOTE_DIR/results"

if ! ssh "$PYNQ_SSH" \
    "test -d $remote_results_q && tar -C $remote_results_q -cf - ." \
    | tar -C "$temporary" -xf -
then
  rm -rf "$temporary"
  echo "error: failed to retrieve FPGA results" >&2
  exit 1
fi

rm -rf "$RESULT_DIR"
mv "$temporary" "$RESULT_DIR"

"$BRIDGE" \
  verify \
  "$VECTOR_DIR" \
  "$RESULT_DIR"

echo
echo "PASS: recovered and verified the encrypted ciphertext result set"
