#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

TOWER_COUNT="${1:-12}"
PRODUCT_COUNT="${2:-32}"
TIMED_RUNS="${3:-3}"
SEED="${4:-0x4096f1e2026}"

PYNQ_SSH="${PYNQ_SSH:-xilinx@pynq}"
REMOTE_DIR="${PYNQ_REMOTE_DIR:-/home/xilinx/jupyter_notebooks/p4ttbo_multitower}"

VECTOR_DIR="$ROOT/vectors/t${TOWER_COUNT}_p${PRODUCT_COUNT}"
RESULT_DIR="$ROOT/results/t${TOWER_COUNT}_p${PRODUCT_COUNT}"
BRIDGE="$ROOT/build/openfhe_multitower_bridge"

retrieve_results() {
  local temporary="${RESULT_DIR}.incoming.$$"
  local remote_results_q

  printf -v remote_results_q '%q' "$REMOTE_DIR/results"

  rm -rf "$temporary"
  mkdir -p "$temporary"

  echo
  echo "Retrieving FPGA results from $PYNQ_SSH:$REMOTE_DIR/results"

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
mkdir -p "$(dirname "$VECTOR_DIR")" "$(dirname "$RESULT_DIR")"

"$BRIDGE" \
  generate \
  "$VECTOR_DIR" \
  "$TOWER_COUNT" \
  "$PRODUCT_COUNT" \
  "$SEED"

"$ROOT/install_openfhe_multitower_board.sh" "$VECTOR_DIR"

ssh -t "$PYNQ_SSH" \
  "sudo bash -lc 'cd \"$REMOTE_DIR\" && ./run_openfhe_multitower_board.sh \"$TIMED_RUNS\"'"

retrieve_results

"$BRIDGE" verify "$VECTOR_DIR" "$RESULT_DIR"

echo
echo "PASS: arbitrary-tower OpenFHE/PYNQ bridge completed end to end"
echo "Vectors: $VECTOR_DIR"
echo "Results: $RESULT_DIR"
