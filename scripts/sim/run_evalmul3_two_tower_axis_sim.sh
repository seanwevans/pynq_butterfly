#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

command -v iverilog >/dev/null || {
  echo "error: missing iverilog" >&2
  echo "Ubuntu/WSL: sudo apt-get install iverilog" >&2
  exit 1
}

BUILD_DIR="$ROOT/build/evalmul3_sim"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

iverilog \
  -g2012 \
  -Wall \
  -s tb_evalmul3_two_tower_axis_core \
  -o "$BUILD_DIR/evalmul3_sim.vvp" \
  "$ROOT/rtl/modmul_barrett60_pipeline_split_core.sv" \
  "$ROOT/rtl/evalmul3_two_tower_axis_core.sv" \
  "$ROOT/tests/rtl/tb_evalmul3_two_tower_axis_core.sv"

vvp "$BUILD_DIR/evalmul3_sim.vvp"
