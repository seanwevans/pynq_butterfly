#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$repo/build/modmul_barrett60_pipeline_split"
binary="$build_dir/tb_modmul_barrett60_pipeline_split_core"

command -v iverilog >/dev/null || {
    echo "error: missing iverilog" >&2
    exit 1
}

command -v vvp >/dev/null || {
    echo "error: missing vvp" >&2
    exit 1
}

mkdir -p "$build_dir"

iverilog \
    -g2012 \
    -Wall \
    -s tb_modmul_barrett60_pipeline_split_core \
    -o "$binary" \
    "$repo/rtl/modmul_barrett60_pipeline_split_core.sv" \
    "$repo/tests/rtl/tb_modmul_barrett60_pipeline_split_core.sv"

vvp "$binary"
