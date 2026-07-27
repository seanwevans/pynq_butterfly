#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

BRIDGE="$ROOT/openfhe_eval_domain_bridge"
VECTOR_DIR="$BRIDGE/vectors/relin_bv_t12_d0"

"$BRIDGE/build.sh"

rm -rf "$VECTOR_DIR"

echo
echo "OPENFHE_FUSED_BV_VECTOR_GENERATION_BEGIN"

"$BRIDGE/build/openfhe_relinearization_probe" \
  --tech bv \
  --towers 12 \
  --digit-size 0 \
  --seed 0x52454c494e \
  --output "$VECTOR_DIR"

echo "OPENFHE_FUSED_BV_VECTOR_GENERATION_END"

"$ROOT/scripts/sim/run_evalmul3_bv_relinearized_openfhe_sim.sh" \
  "$VECTOR_DIR"
