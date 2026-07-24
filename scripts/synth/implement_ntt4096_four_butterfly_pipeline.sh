#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tcl="$repo/scripts/synth/implement_ntt4096_four_butterfly_pipeline.tcl"
vivado_bat="${VIVADO_BAT:-/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat}"

[[ -f "$tcl" ]] || {
    echo "error: Tcl script not found: $tcl" >&2
    exit 1
}

[[ -f "$vivado_bat" ]] || {
    echo "error: Vivado batch launcher not found: $vivado_bat" >&2
    exit 1
}

command -v cmd.exe >/dev/null || {
    echo "error: WSL Windows interop unavailable: cmd.exe not found" >&2
    exit 1
}

build_dir="$repo/build/ntt4096_four_butterfly_pipeline"
mkdir -p "$build_dir"

cmd_file="$build_dir/run_vivado.cmd"

repo_win="$(wslpath -w "$repo")"
tcl_win="$(wslpath -w "$tcl")"
vivado_win="$(wslpath -w "$vivado_bat")"

python3 - "$cmd_file" "$repo_win" "$vivado_win" "$tcl_win" <<'PY'
from pathlib import Path
import sys

cmd_path = Path(sys.argv[1])
repo = sys.argv[2]
vivado = sys.argv[3]
tcl = sys.argv[4]

cmd_path.write_bytes(
    (
        "@echo off\r\n"
        f'cd /d "{repo}"\r\n'
        f'call "{vivado}" -mode batch -source "{tcl}"\r\n'
        "exit /b %ERRORLEVEL%\r\n"
    ).encode("ascii")
)
PY

cmd_win="$(wslpath -w "$cmd_file")"

cmd.exe /d /c "$cmd_win"
