#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

TOWER_COUNT="${1:-12}"
CIPHERTEXT_COUNT="${2:-16}"
TIMED_RUNS="${3:-3}"
SEED="${4:-0xc1f40962026}"

PYNQ_SSH="${PYNQ_SSH:-xilinx@pynq}"
REMOTE_DIR="${PYNQ_REMOTE_DIR:-/home/xilinx/jupyter_notebooks/p4ttbo_ciphertext}"

VECTOR_DIR="$ROOT/vectors/t${TOWER_COUNT}_c${CIPHERTEXT_COUNT}"
RESULT_DIR="$ROOT/results/t${TOWER_COUNT}_c${CIPHERTEXT_COUNT}"
BRIDGE="$ROOT/build/openfhe_ciphertext_bridge"

retrieve_results() {
  local temporary="${RESULT_DIR}.incoming.$$"
  local remote_results_q

  printf -v remote_results_q '%q' "$REMOTE_DIR/results"

  rm -rf "$temporary"
  mkdir -p "$temporary"

  echo
  echo "Retrieving FPGA results from:"
  echo "  $PYNQ_SSH:$REMOTE_DIR/results"

  if ! ssh "$PYNQ_SSH" \
      "test -d $remote_results_q && tar -C $remote_results_q -cf - ." \
      | tar -C "$temporary" -xf -
  then
    rm -rf "$temporary"
    echo "error: failed to retrieve FPGA results" >&2
    return 1
  fi

  rm -rf "$RESULT_DIR"
  mv "$temporary" "$RESULT_DIR"
}

"$ROOT/build.sh"

rm -rf "$VECTOR_DIR" "$RESULT_DIR"

mkdir -p \
  "$(dirname "$VECTOR_DIR")" \
  "$(dirname "$RESULT_DIR")"

"$BRIDGE" \
  generate \
  "$VECTOR_DIR" \
  "$TOWER_COUNT" \
  "$CIPHERTEXT_COUNT" \
  "$SEED"

"$ROOT/install_openfhe_ciphertext_board.sh" \
  "$VECTOR_DIR"

ssh -t "$PYNQ_SSH" \
  "sudo bash -lc \
    'cd \"$REMOTE_DIR\" \
    && ./run_openfhe_ciphertext_board.sh \"$TIMED_RUNS\"'"

retrieve_results

"$BRIDGE" \
  verify \
  "$VECTOR_DIR" \
  "$RESULT_DIR"

echo
echo "PASS: encrypted BGVRNS pre-relinearization bridge completed end to end"
echo "Vectors: $VECTOR_DIR"
echo "Results: $RESULT_DIR"
