#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

TOWER_COUNT="${1:-12}"
CIPHERTEXT_COUNT="${2:-4}"
SEED="${3:-0xe1a140962026}"

"$ROOT/openfhe_eval_domain_bridge/build.sh"

VECTOR_DIR="$ROOT/openfhe_eval_domain_bridge/vectors/t${TOWER_COUNT}_c${CIPHERTEXT_COUNT}"

"$ROOT/openfhe_eval_domain_bridge/build/openfhe_eval_domain_bridge" \
  generate \
  "$VECTOR_DIR" \
  "$TOWER_COUNT" \
  "$CIPHERTEXT_COUNT" \
  "$SEED"

echo
"$ROOT/scripts/sim/run_evalmul3_two_tower_axis_sim.sh"

echo
echo "PASS: evaluation-domain fused software/RTL checkpoint"
echo "Vectors: $VECTOR_DIR"
