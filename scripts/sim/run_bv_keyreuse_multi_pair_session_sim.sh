#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

PROBE_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
GENERATED_DIR="${2:-$ROOT/tests/fixtures/bv_keyreuse_multi_pair_session}"
BUILD_DIR="${3:-$ROOT/build/bv_keyreuse_multi_pair_session_sim}"

mkdir -p \
  "$GENERATED_DIR" \
  "$BUILD_DIR"

python3 \
  "$ROOT/openfhe_eval_domain_bridge/prepare_bv_keyreuse_coefficient_major_vectors.py" \
  "$PROBE_DIR" \
  "$GENERATED_DIR" \
  --coefficients 32 \
  --ciphertexts 8

echo
echo "BV_KEYREUSE_MULTI_PAIR_SESSION_SIM_COMPILE_BEGIN"

iverilog \
  -g2012 \
  -Wall \
  -s tb_evalmul3_bv_keyreuse_multi_pair_session_axis_core \
  -o "$BUILD_DIR/bv_keyreuse_multi_pair_session.vvp" \
  "$ROOT/tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv" \
  "$ROOT/rtl/evalmul3_bv_keyreuse_drain_overlap_axis_core.sv" \
  "$ROOT/rtl/evalmul3_bv_keyreuse_multi_pair_session_axis_core.sv" \
  "$ROOT/tests/rtl/tb_evalmul3_bv_keyreuse_multi_pair_session_axis_core.sv"

echo "BV_KEYREUSE_MULTI_PAIR_SESSION_SIM_COMPILE_END"
echo "BV_KEYREUSE_MULTI_PAIR_SESSION_SIM_RUN_BEGIN"

set +e

timeout \
  300 \
  vvp \
  "$BUILD_DIR/bv_keyreuse_multi_pair_session.vvp" \
  "+VECTOR_ROOT=$GENERATED_DIR"

status=$?

set -e

if [[ $status -eq 124 ]]; then
  echo \
    "error: multi-pair session vvp exceeded 300 real seconds" \
    >&2

  exit 124
fi

if [[ $status -ne 0 ]]; then
  echo \
    "error: multi-pair session vvp failed with status $status" \
    >&2

  exit "$status"
fi

echo "BV_KEYREUSE_MULTI_PAIR_SESSION_SIM_RUN_END"
echo
echo "PASS: exact persistent-output multi-pair session checkpoint complete"
