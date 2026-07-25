#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

BRIDGE="$ROOT/openfhe_eval_domain_bridge"
VECTOR_ROOT="$BRIDGE/vectors"

"$BRIDGE/build.sh"

rm -rf \
  "$VECTOR_ROOT/relin_hybrid_t12" \
  "$VECTOR_ROOT/relin_bv_t12_d0"

echo
echo "OPENFHE_RELINEARIZATION_HYBRID_BEGIN"

"$BRIDGE/build/openfhe_relinearization_probe" \
  --tech hybrid \
  --towers 12 \
  --num-large-digits 3 \
  --seed 0x52454c494e \
  --output "$VECTOR_ROOT/relin_hybrid_t12"

echo "OPENFHE_RELINEARIZATION_HYBRID_END"

echo
echo "OPENFHE_RELINEARIZATION_BV_BEGIN"

"$BRIDGE/build/openfhe_relinearization_probe" \
  --tech bv \
  --towers 12 \
  --digit-size 0 \
  --seed 0x52454c494e \
  --output "$VECTOR_ROOT/relin_bv_t12_d0"

echo "OPENFHE_RELINEARIZATION_BV_END"

echo
echo "PASS: exact OpenFHE relinearization probes completed"
