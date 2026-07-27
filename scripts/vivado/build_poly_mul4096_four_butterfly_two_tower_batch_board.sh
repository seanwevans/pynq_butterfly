#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
vivado_bat="${VIVADO_BAT:-/mnt/f/Xilinx/Vivado/2024.1/bin/vivado.bat}"

package_tcl="$repo/scripts/package/package_poly_mul4096_four_butterfly_two_tower_batch_ip.tcl"
integrate_tcl="$repo/scripts/integrate/integrate_poly_mul4096_four_butterfly_two_tower_batch_dma.tcl"

for path in "$package_tcl" "$integrate_tcl" "$vivado_bat"; do
    [[ -f "$path" ]] || {
        echo "error: required file not found: $path" >&2
        exit 1
    }
done

command -v cmd.exe >/dev/null || {
    echo "error: WSL Windows interop unavailable: cmd.exe not found" >&2
    exit 1
}

build_dir="$repo/build/poly_mul4096_four_butterfly_batch_board"
mkdir -p "$build_dir"
cmd_file="$build_dir/build_batch_board_overlay.cmd"

repo_win="$(wslpath -w "$repo")"
vivado_win="$(wslpath -w "$vivado_bat")"
package_win="$(wslpath -w "$package_tcl")"
integrate_win="$(wslpath -w "$integrate_tcl")"

python3 - \
    "$cmd_file" \
    "$repo_win" \
    "$vivado_win" \
    "$package_win" \
    "$integrate_win" <<'PY2'
from pathlib import Path
import sys

cmd_path = Path(sys.argv[1])
repo = sys.argv[2]
vivado = sys.argv[3]
package_tcl = sys.argv[4]
integrate_tcl = sys.argv[5]

cmd_path.write_bytes(
    (
        "@echo off\r\n"
        f'cd /d "{repo}"\r\n'
        f'call "{vivado}" -mode batch -source "{package_tcl}"\r\n'
        "if errorlevel 1 exit /b %ERRORLEVEL%\r\n"
        f'call "{vivado}" -mode batch -source "{integrate_tcl}"\r\n'
        "exit /b %ERRORLEVEL%\r\n"
    ).encode("ascii")
)
PY2

cmd_win="$(wslpath -w "$cmd_file")"
cmd.exe /d /c "$cmd_win"
