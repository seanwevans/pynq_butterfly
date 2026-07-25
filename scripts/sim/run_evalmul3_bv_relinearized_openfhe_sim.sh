#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

PROBE_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
GENERATED_DIR="${2:-$ROOT/tests/generated/evalmul3_bv_relinearized_openfhe}"
BUILD_DIR="${3:-$ROOT/build/evalmul3_bv_relinearized_sim}"

mkdir -p \
  "$GENERATED_DIR" \
  "$BUILD_DIR"

python3 \
  "$ROOT/openfhe_eval_domain_bridge/prepare_evalmul3_bv_relinearized_vectors.py" \
  "$PROBE_DIR" \
  "$GENERATED_DIR" \
  --coefficients 32

echo
echo "EVALMUL3_BV_RELINEARIZED_SIM_COMPILE_BEGIN"

iverilog \
  -g2012 \
  -Wall \
  -s tb_evalmul3_bv_relinearize_two_tower_axis_core \
  -o "$BUILD_DIR/evalmul3_bv_relinearized.vvp" \
  "$ROOT/tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv" \
  "$ROOT/rtl/evalmul3_two_tower_axis_core.sv" \
  "$ROOT/rtl/bv_keyswitch_mac_two_tower_axis_core.sv" \
  "$ROOT/rtl/evalmul3_bv_relinearize_two_tower_axis_core.sv" \
  "$ROOT/tests/rtl/tb_evalmul3_bv_relinearize_two_tower_axis_core.sv"

echo "EVALMUL3_BV_RELINEARIZED_SIM_COMPILE_END"
echo "EVALMUL3_BV_RELINEARIZED_SIM_RUN_BEGIN"

set +e

timeout \
  180 \
  vvp \
  "$BUILD_DIR/evalmul3_bv_relinearized.vvp" \
  "+VECTOR_ROOT=$GENERATED_DIR"

status=$?

set -e

if [[ $status -eq 124 ]]; then
  echo \
    "error: vvp exceeded 180 real seconds before the RTL watchdog fired" \
    >&2

  exit 124
fi

if [[ $status -ne 0 ]]; then
  echo \
    "error: vvp failed with status $status" \
    >&2

  exit "$status"
fi

echo "EVALMUL3_BV_RELINEARIZED_SIM_RUN_END"
echo
echo "PASS: exact fused OpenFHE BV relinearization RTL checkpoint complete"
