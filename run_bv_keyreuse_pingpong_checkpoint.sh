#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

VECTOR_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"

[[ -f "$VECTOR_DIR/metadata.json" ]] || {
  echo "error: missing BV probe vectors: $VECTOR_DIR" >&2
  echo "run ./run_evalmul3_bv_relinearized_checkpoint.sh first" >&2
  exit 1
}

"$ROOT/scripts/sim/run_bv_keyreuse_pingpong_sim.sh" \
  "$VECTOR_DIR"
