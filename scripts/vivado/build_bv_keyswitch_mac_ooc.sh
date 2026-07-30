#!/usr/bin/env bash
set -euo pipefail

ROOT="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
  pwd
)"

VIVADO_BAT="${VIVADO_BAT:-/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat}"
WORK_DIR="${BV_KEYSWITCH_MAC_OOC_WORK:-/mnt/f/v/bv_keyswitch_mac_ooc}"

[[ -f "$VIVADO_BAT" ]] || {
  echo "error: Vivado batch file not found: $VIVADO_BAT" >&2
  exit 1
}

required=(
  "$ROOT/rtl/modmul_barrett60_pipeline_split_core.sv"
  "$ROOT/rtl/bv_keyswitch_mac_two_tower_axis_core.sv"
  "$ROOT/scripts/vivado/build_bv_keyswitch_mac_ooc.tcl"
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || {
    echo "error: missing required file: $path" >&2
    exit 1
  }
done

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

repo_windows="$(wslpath -w "$ROOT")"
work_windows="$(wslpath -w "$WORK_DIR")"
vivado_windows="$(wslpath -w "$VIVADO_BAT")"
tcl_windows="$repo_windows\\scripts\\vivado\\build_bv_keyswitch_mac_ooc.tcl"

cmd_file="$WORK_DIR/run_bv_keyswitch_mac_ooc.cmd"

cat >"$cmd_file" <<EOF
@echo off
call "$vivado_windows" -mode batch -nolog -nojournal ^
  -source "$tcl_windows" ^
  -tclargs "$repo_windows" "$work_windows"
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

pass_marker='PASS: standalone exact BV key-switch MAC routed at 100 MHz'

if [[ ! -f "$summary" ]] \
  || ! tr -d '\r' <"$summary" | grep -Fxq "$pass_marker"; then
  echo "error: Vivado did not record the OOC PASS marker" >&2
  status=1
fi

exit "$status"
