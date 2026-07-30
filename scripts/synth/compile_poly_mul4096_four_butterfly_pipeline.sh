#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
rtl="$repo/rtl"
build="$repo/build/poly_mul4096_four_butterfly_pipeline"
binary="$build/tb_poly_mul4096_four_butterfly_pipeline_runtime_profile_core"

command -v iverilog >/dev/null || {
    echo "error: missing iverilog" >&2
    exit 1
}

command -v vvp >/dev/null || {
    echo "error: missing vvp" >&2
    exit 1
}

required=(
    "$rtl/modmul_barrett60_pipeline_split_core.sv"
    "$rtl/ntt4096_dual_mode_butterfly_pipeline_core.sv"
    "$rtl/ntt4096_profile_bram_dual_read.sv"
    "$rtl/ntt4096_profile_bram_four_read.sv"
    "$rtl/ntt4096_coeff_bank_512x32.sv"
    "$rtl/ntt4096_eight_bank_coeff_store_runtime.sv"
    "$rtl/ntt4096_four_butterfly_schedule_core.sv"
    "$rtl/poly_mul4096_four_lane_arithmetic_core.sv"
    "$rtl/poly_mul4096_four_butterfly_pipeline_runtime_profile_core.sv"
    "$repo/tests/rtl/tb_poly_mul4096_four_butterfly_pipeline_runtime_profile_core.sv"
)

for path in "${required[@]}"; do
    [[ -f "$path" ]] || {
        echo "error: required file not found: $path" >&2
        exit 1
    }
done

[[ -d "$rtl/generated_dual_butterfly_poly" ]] || {
    echo "error: missing generated OpenFHE product vectors" >&2
    exit 1
}

mkdir -p "$build"

iverilog \
    -g2012 \
    -Wall \
    -s tb_poly_mul4096_four_butterfly_pipeline_runtime_profile_core \
    -o "$binary" \
    "${required[@]}"

(
    cd "$rtl"
    vvp "$binary"
)
