#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
  pwd
)"

VIVADO_BAT="${VIVADO_BAT:-/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat}"
WORK_DIR="${BV_KEYREUSE_PINGPONG_DMA150_WORK:-/mnt/f/v/bv_keyreuse_pingpong_dma150_overlay}"
DEPLOY_DIR="$ROOT/deploy/bv_keyreuse_pingpong_dma150"

[[ -f "$VIVADO_BAT" ]] || {
  echo "error: Vivado batch file not found: $VIVADO_BAT" >&2
  exit 1
}

required=(
  "$ROOT/rtl/modmul_barrett60_pipeline_split_core.sv"
  "$ROOT/rtl/evalmul3_bv_keyreuse_pingpong_axis_core.sv"
  "$ROOT/rtl/evalmul3_bv_keyreuse_pingpong_dma_wrapper.v"
  "$ROOT/scripts/vivado/build_bv_keyreuse_pingpong_dma150_overlay.tcl"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required file: $path" >&2
    exit 1
  }
done

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$DEPLOY_DIR"

rm -f \
  "$DEPLOY_DIR/evalmul3_bv_keyreuse_pingpong_dma150.bit" \
  "$DEPLOY_DIR/evalmul3_bv_keyreuse_pingpong_dma150.hwh" \
  "$DEPLOY_DIR/build_summary.txt" \
  "$DEPLOY_DIR/routed_timing_summary.rpt" \
  "$DEPLOY_DIR/routed_utilization.rpt"

repo_windows="$(wslpath -w "$ROOT")"
work_windows="$(wslpath -w "$WORK_DIR")"
deploy_windows="$(wslpath -w "$DEPLOY_DIR")"
vivado_windows="$(wslpath -w "$VIVADO_BAT")"
tcl_windows="$repo_windows\\scripts\\vivado\\build_bv_keyreuse_pingpong_dma150_overlay.tcl"

cmd_file="$WORK_DIR/run_bv_keyreuse_pingpong_dma150_overlay.cmd"

cat >"$cmd_file" <<EOF
@echo off
call "$vivado_windows" -mode batch -nolog -nojournal ^
  -source "$tcl_windows" ^
  -tclargs "$repo_windows" "$work_windows" "$deploy_windows"
exit /b %ERRORLEVEL%
EOF

set +e

cmd.exe \
  /d \
  /c \
  "$(wslpath -w "$cmd_file")"

status=$?

set -e

summary="$WORK_DIR/build_summary.txt"

echo

if [[ -f "$summary" ]]; then
  tr -d '\r' <"$summary"
else
  echo "error: Vivado did not produce $summary" >&2
  status=1
fi

marker='PASS: ping-pong coefficient-major evaluation-key-reuse dual-clock DMA overlay routed'

if [[ ! -f "$summary" ]] \
  || ! tr -d '\r' <"$summary" | grep -Fxq "$marker"; then
  echo "error: Vivado did not record the ping-pong overlay PASS marker" >&2
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  cp -f \
    "$WORK_DIR/routed_timing_summary.rpt" \
    "$DEPLOY_DIR/"

  cp -f \
    "$WORK_DIR/routed_utilization.rpt" \
    "$DEPLOY_DIR/"

  cp -f \
    "$WORK_DIR/build_summary.txt" \
    "$DEPLOY_DIR/"

  echo
  echo "Deploy:"

  for artifact in \
    "$DEPLOY_DIR/evalmul3_bv_keyreuse_pingpong_dma150.bit" \
    "$DEPLOY_DIR/evalmul3_bv_keyreuse_pingpong_dma150.hwh" \
    "$DEPLOY_DIR/build_summary.txt"; do
    if [[ -f "$artifact" ]]; then
      echo "  PASS $artifact"
    else
      echo "  MISS $artifact"
      status=1
    fi
  done
fi

exit "$status"
