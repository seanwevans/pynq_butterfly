#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

PROBE_DIR="${1:-$ROOT/openfhe_eval_domain_bridge/vectors/relin_bv_t12_d0}"
GENERATED_DIR="${2:-$ROOT/tests/generated/bv_keyswitch_mac_openfhe}"
BUILD_DIR="${3:-$ROOT/build/bv_keyswitch_mac_sim}"

mkdir -p \
  "$GENERATED_DIR" \
  "$BUILD_DIR"

python3 \
  "$ROOT/openfhe_eval_domain_bridge/prepare_bv_keyswitch_mac_vectors.py" \
  "$PROBE_DIR" \
  "$GENERATED_DIR" \
  --coefficients 32

echo
echo "BV_KEYSWITCH_MAC_SIM_COMPILE_BEGIN"

iverilog \
  -g2012 \
  -Wall \
  -s tb_bv_keyswitch_mac_two_tower_axis_core \
  -o "$BUILD_DIR/bv_keyswitch_mac.vvp" \
  "$ROOT/tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv" \
  "$ROOT/rtl/bv_keyswitch_mac_two_tower_axis_core.sv" \
  "$ROOT/tests/rtl/tb_bv_keyswitch_mac_two_tower_axis_core.sv"

echo "BV_KEYSWITCH_MAC_SIM_COMPILE_END"
echo "BV_KEYSWITCH_MAC_SIM_RUN_BEGIN"

set +e

timeout \
  120 \
  vvp \
  "$BUILD_DIR/bv_keyswitch_mac.vvp" \
  "+VECTOR_ROOT=$GENERATED_DIR"

status=$?

set -e

if [[ $status -eq 124 ]]; then
  echo \
    "error: vvp exceeded 120 real seconds before the RTL watchdog fired" \
    >&2

  exit 124
fi

if [[ $status -ne 0 ]]; then
  echo \
    "error: vvp failed with status $status" \
    >&2

  exit "$status"
fi

echo "BV_KEYSWITCH_MAC_SIM_RUN_END"
echo
echo "PASS: exact OpenFHE BV key-switch MAC RTL checkpoint complete"
