#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rtl="$repo/rtl"
build="$repo/build/ntt4096_shared_ab_pipeline"
binary="$build/tb_ntt4096_four_butterfly_shared_ab_core"

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
    "$rtl/ntt4096_four_butterfly_pipeline_engine_core.sv"
    "$rtl/ntt4096_four_butterfly_shared_ab_core.sv"
    "$rtl/tb_ntt4096_four_butterfly_shared_ab_core.sv"
)

for path in "${required[@]}"; do
    [[ -f "$path" ]] || {
        echo "error: required file not found: $path" >&2
        exit 1
    }
done

[[ -d "$rtl/generated_four_butterfly_ntt" ]] || {
    echo "error: generated vector directory not found:" >&2
    echo "  $rtl/generated_four_butterfly_ntt" >&2
    exit 1
}

mkdir -p "$build"

iverilog \
    -g2012 \
    -Wall \
    -s tb_ntt4096_four_butterfly_shared_ab_core \
    -o "$binary" \
    "${required[@]}"

(
    cd "$rtl"
    vvp "$binary"
)
