#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

VIVADO_BAT="${VIVADO_BAT:-/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat}"
WORK_DIR="${EVALMUL3_OOC_WORK:-/mnt/f/v/evalmul3_ooc}"

[[ -f "$VIVADO_BAT" ]] || {
  echo "error: Vivado batch file not found: $VIVADO_BAT" >&2
  exit 1
}

required=(
  "$ROOT/rtl/modmul_barrett60_pipeline_split_core.sv"
  "$ROOT/rtl/evalmul3_two_tower_axis_core.sv"
  "$ROOT/scripts/vivado/build_evalmul3_ooc.tcl"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required file: $path" >&2
    exit 1
  }
done

mkdir -p "$WORK_DIR"

repo_windows="$(wslpath -w "$ROOT")"
work_windows="$(wslpath -w "$WORK_DIR")"
vivado_windows="$(wslpath -w "$VIVADO_BAT")"
tcl_windows="$repo_windows\\scripts\\vivado\\build_evalmul3_ooc.tcl"

cmd_file="$WORK_DIR/run_evalmul3_ooc.cmd"

cat >"$cmd_file" <<EOF
@echo off
call "$vivado_windows" -mode batch -nolog -nojournal ^
  -source "$tcl_windows" ^
  -tclargs "$repo_windows" "$work_windows"
exit /b %ERRORLEVEL%
EOF

set +e
cmd.exe /d /c "$(wslpath -w "$cmd_file")"
status=$?
set -e

summary="$WORK_DIR/build_summary.txt"

echo
if [[ -f "$summary" ]]; then
  cat "$summary"
else
  echo "error: Vivado did not produce $summary" >&2
fi

echo
echo "Artifacts:"
artifacts=(
  "$WORK_DIR/routed_before_physopt.dcp"
  "$WORK_DIR/routed.dcp"
  "$WORK_DIR/routed_timing_summary.rpt"
  "$WORK_DIR/routed_utilization.rpt"
  "$WORK_DIR/routed_critical_paths.rpt"
)

for artifact in "${artifacts[@]}"; do
  if [[ -f "$artifact" ]]; then
    echo "  PASS $artifact"
  else
    echo "  MISS $artifact"
  fi
done

exit "$status"
