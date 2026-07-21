#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vivado="${VIVADO_BAT:-/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat}"
tcl="$repo/implement_modmul_barrett60_pipeline_split.tcl"

[[ -f "$vivado" ]] || {
    echo "error: Vivado launcher not found: $vivado" >&2
    exit 1
}

[[ -f "$tcl" ]] || {
    echo "error: Tcl script not found: $tcl" >&2
    exit 1
}

command -v cmd.exe >/dev/null || {
    echo "error: WSL Windows interop is unavailable: cmd.exe not found" >&2
    exit 1
}

build_dir="$repo/build/modmul_barrett60_pipeline_split"
mkdir -p "$build_dir"

cmd_file="$build_dir/run_vivado.cmd"

repo_win="$(wslpath -w "$repo")"
vivado_win="$(wslpath -w "$vivado")"
tcl_win="$(wslpath -w "$tcl")"

python3 - "$cmd_file" "$repo_win" "$vivado_win" "$tcl_win" <<'PY'
from pathlib import Path
import sys

cmd_path = Path(sys.argv[1])
repo = sys.argv[2]
vivado = sys.argv[3]
tcl = sys.argv[4]

content = (
    "@echo off\r\n"
    f'cd /d "{repo}"\r\n'
    f'call "{vivado}" -mode batch -source "{tcl}"\r\n'
    "exit /b %ERRORLEVEL%\r\n"
)

cmd_path.write_bytes(content.encode("ascii"))
PY

cmd_win="$(wslpath -w "$cmd_file")"

cmd.exe /d /c "$cmd_win"
