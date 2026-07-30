#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

PROBE_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
GENERATED_DIR="${2:-$ROOT/tests/generated/bv_keyreuse_coefficient_major}"
BUILD_DIR="${3:-$ROOT/build/bv_keyreuse_coefficient_major_sim}"

mkdir -p \
  "$GENERATED_DIR" \
  "$BUILD_DIR"

python3 \
  "$ROOT/host/openfhe/python/pynq_butterfly/cli/prepare_bv_keyreuse_coefficient_major_vectors.py" \
  "$PROBE_DIR" \
  "$GENERATED_DIR" \
  --coefficients 32 \
  --ciphertexts 8

echo
echo "BV_KEYREUSE_COEFFICIENT_MAJOR_SIM_COMPILE_BEGIN"

iverilog \
  -g2012 \
  -Wall \
  -s tb_evalmul3_bv_keyreuse_coefficient_major_axis_core \
  -o "$BUILD_DIR/bv_keyreuse_coefficient_major.vvp" \
  "$ROOT/tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv" \
  "$ROOT/rtl/evalmul3_bv_keyreuse_coefficient_major_axis_core.sv" \
  "$ROOT/tests/rtl/tb_evalmul3_bv_keyreuse_coefficient_major_axis_core.sv"

echo "BV_KEYREUSE_COEFFICIENT_MAJOR_SIM_COMPILE_END"
echo "BV_KEYREUSE_COEFFICIENT_MAJOR_SIM_RUN_BEGIN"

set +e

timeout \
  240 \
  vvp \
  "$BUILD_DIR/bv_keyreuse_coefficient_major.vvp" \
  "+VECTOR_ROOT=$GENERATED_DIR"

status=$?

set -e

if [[ $status -eq 124 ]]; then
  echo \
    "error: vvp exceeded 240 real seconds" \
    >&2

  exit 124
fi

if [[ $status -ne 0 ]]; then
  echo \
    "error: vvp failed with status $status" \
    >&2

  exit "$status"
fi

echo "BV_KEYREUSE_COEFFICIENT_MAJOR_SIM_RUN_END"
echo
echo "PASS: exact coefficient-major evaluation-key-reuse RTL checkpoint complete"
