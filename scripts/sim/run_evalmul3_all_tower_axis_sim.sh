#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

BUILD_DIR="${EVALMUL3_ALLPAIRS_SIM_WORK:-/tmp/evalmul3_allpairs_sim}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "EVALMUL3_ALLPAIRS_SIM_COMPILE_BEGIN"

set +e
timeout 60s \
  iverilog \
    -g2012 \
    -Wall \
    -s tb_evalmul3_all_tower_axis_core \
    -o "$BUILD_DIR/tb_evalmul3_all_tower_axis_core.vvp" \
    "$ROOT/tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv" \
    "$ROOT/rtl/evalmul3_two_tower_axis_core.sv" \
    "$ROOT/rtl/evalmul3_all_tower_axis_core.sv" \
    "$ROOT/tests/rtl/tb_evalmul3_all_tower_axis_core.sv"
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  if [[ "$status" -eq 124 ]]; then
    echo "error: Icarus compilation exceeded 60 seconds" >&2
  else
    echo "error: Icarus compilation failed with status $status" >&2
  fi

  exit "$status"
fi

echo "EVALMUL3_ALLPAIRS_SIM_COMPILE_END"
echo "EVALMUL3_ALLPAIRS_SIM_RUN_BEGIN"

set +e
timeout 60s \
  vvp "$BUILD_DIR/tb_evalmul3_all_tower_axis_core.vvp"
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  if [[ "$status" -eq 124 ]]; then
    echo "error: vvp exceeded 60 real seconds before the 512-cycle RTL watchdog fired" >&2
  else
    echo "error: vvp failed with status $status" >&2
  fi

  exit "$status"
fi

echo "EVALMUL3_ALLPAIRS_SIM_RUN_END"
