#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source_file="$repo/tb_poly_mul4096_four_butterfly_two_tower_axis_core.sv"
destination="$repo/rtl/tb_poly_mul4096_four_butterfly_two_tower_axis_core.sv"

[[ -f "$source_file" ]] || {
    echo "error: replacement testbench not found: $source_file" >&2
    exit 1
}

cp -f \
    "$source_file" \
    "$destination"

echo "PASS: installed clean concurrent AXI testbench"

exec \
    "$repo/compile_poly_mul4096_four_butterfly_two_tower_axis.sh"
