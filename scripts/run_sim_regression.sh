#!/usr/bin/env bash

# Compile and run the Icarus Verilog testbenches in rtl/.
#
# Usage:
#     scripts/run_sim_regression.sh [--quick|--all] [tb_name ...]
#
# --all (default) runs every rtl/tb_*.sv testbench.
# --quick skips the long-running full-transform and full-product
# testbenches and finishes in about a minute.
# Explicit testbench names (with or without .sv) run only those.
#
# A testbench passes when vvp exits zero and prints no FAIL line.
# Every testbench signals failure through $fatal, which makes vvp
# exit nonzero.

set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rtl="$repo/rtl"
build="$repo/build/sim"

per_test_timeout="${SIM_TEST_TIMEOUT:-1800}"

command -v iverilog >/dev/null || {
    echo "error: missing iverilog" >&2
    exit 1
}

command -v vvp >/dev/null || {
    echo "error: missing vvp" >&2
    exit 1
}

# Package definitions must be compiled explicitly; -y library search
# resolves ordinary modules by file name but cannot locate packages.
packages=(
    "$rtl/ntt256_profile_pkg.sv"
    "$rtl/ntt4096_profile_pkg.sv"
)

# Integration testbenches that support the documented fast-simulation
# mode (docs/history/readme-fast-sim.md): compiled with -DFAST_MODMUL and the exact
# behavioral modmul_core_fast_sim.sv in place of the iterative
# hardware modmul_core.sv. Output correctness is still checked
# exactly; the hardware multiplier itself is covered by its own unit
# testbenches.
fast_modmul_tests=(
    tb_poly_mul4096_dual_butterfly_runtime_profile_core
    tb_poly_mul4096_dual_butterfly_two_tower_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_batch2_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_buffered4_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_prefetch4_axis_core
)

# Testbenches whose input vectors are not in the repository.
# rtl/generated_dual_butterfly_prefetch4/ holds a four-product
# OpenFHE vector set produced by
# prepare_dual_butterfly_prefetch4_vectors.py from an OpenFHE bridge
# run; regenerating it requires OpenFHE.
skipped_tests=(
    tb_poly_mul4096_dual_butterfly_two_tower_buffered4_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_prefetch4_axis_core
)

# Full-transform and full-product simulations that run for minutes
# under Icarus. --quick skips these.
slow_tests=(
    tb_forward_ntt4096_core
    tb_forward_ntt4096_dual_dif_core
    tb_inverse_ntt4096_core
    tb_ntt4096_cyclic_core
    tb_ntt4096_dif_cyclic_core
    tb_ntt4096_four_butterfly_pipeline_transform_core
    tb_ntt4096_four_butterfly_transform_core
    tb_poly_mul256_axis_batch_core
    tb_poly_mul4096_axis_core
    tb_poly_mul4096_core
    tb_poly_mul4096_dual_butterfly_runtime_profile_core
    tb_poly_mul4096_dual_butterfly_two_tower_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_batch2_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_buffered4_axis_core
    tb_poly_mul4096_dual_butterfly_two_tower_prefetch4_axis_core
    tb_poly_mul4096_runtime_profile_axis_core
    tb_poly_mul4096_runtime_profile_core
    tb_poly_mul4096_runtime_profile_dual_axis_core
    tb_poly_mul4096_two_bank_axis_core
    tb_poly_mul4096_two_bank_core
)

# Testbenches under tests/rtl/ covering the evaluation-domain line.
#
# These are compiled from explicit source lists rather than -y library
# search: tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv
# declares the same module name as rtl/modmul_barrett60_pipeline_split_core.sv,
# so letting iverilog resolve by filename would pick the wrong multiplier.
# The lists mirror the scripts/sim/ launchers.

declare -A tests_rtl_sources=(
    [tb_evalmul3_two_tower_axis_core]="\
rtl/modmul_barrett60_pipeline_split_core.sv \
rtl/evalmul3_two_tower_axis_core.sv"

    [tb_evalmul3_all_tower_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/evalmul3_two_tower_axis_core.sv \
rtl/evalmul3_all_tower_axis_core.sv"

    [tb_bv_keyswitch_mac_two_tower_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/bv_keyswitch_mac_two_tower_axis_core.sv"

    [tb_evalmul3_bv_relinearize_two_tower_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/evalmul3_two_tower_axis_core.sv \
rtl/bv_keyswitch_mac_two_tower_axis_core.sv \
rtl/evalmul3_bv_relinearize_two_tower_axis_core.sv"

    [tb_evalmul3_bv_keyreuse_coefficient_major_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/evalmul3_bv_keyreuse_coefficient_major_axis_core.sv"

    [tb_evalmul3_bv_keyreuse_pingpong_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/evalmul3_bv_keyreuse_pingpong_axis_core.sv"

    [tb_evalmul3_bv_keyreuse_drain_overlap_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/evalmul3_bv_keyreuse_drain_overlap_axis_core.sv"

    [tb_evalmul3_bv_keyreuse_multi_pair_session_axis_core]="\
tests/rtl/modmul_barrett60_pipeline_split_core_fast_sim.sv \
rtl/evalmul3_bv_keyreuse_drain_overlap_axis_core.sv \
rtl/evalmul3_bv_keyreuse_multi_pair_session_axis_core.sv"
)

# Vector directory passed to each testbench as +VECTOR_ROOT.
# A testbench whose directory holds no .hex files is skipped, so a clone
# without regenerated OpenFHE vectors still reports green.

declare -A tests_rtl_vectors=(
    [tb_evalmul3_two_tower_axis_core]=tests/generated/evalmul3_bv_relinearized_openfhe
    [tb_evalmul3_all_tower_axis_core]=tests/generated/evalmul3_bv_relinearized_openfhe
    [tb_bv_keyswitch_mac_two_tower_axis_core]=tests/generated/bv_keyswitch_mac_openfhe
    [tb_evalmul3_bv_relinearize_two_tower_axis_core]=tests/generated/evalmul3_bv_relinearized_openfhe
    [tb_evalmul3_bv_keyreuse_coefficient_major_axis_core]=tests/generated/bv_keyreuse_coefficient_major
    [tb_evalmul3_bv_keyreuse_pingpong_axis_core]=tests/generated/bv_keyreuse_pingpong
    [tb_evalmul3_bv_keyreuse_drain_overlap_axis_core]=tests/generated/bv_keyreuse_drain_overlap
    [tb_evalmul3_bv_keyreuse_multi_pair_session_axis_core]=tests/generated/bv_keyreuse_multi_pair_session
)

in_tests_rtl() {
    [ -n "${tests_rtl_sources[$1]+set}" ]
}

in_list() {
    local needle="$1"
    shift
    local candidate
    for candidate in "$@"; do
        [ "$candidate" = "$needle" ] && return 0
    done
    return 1
}

mode=--all
tests=()

for argument in "$@"; do
    case "$argument" in
        --quick|--all)
            mode="$argument"
            ;;
        *)
            tests+=("$(basename "$argument" .sv)")
            ;;
    esac
done

if [ "${#tests[@]}" -eq 0 ]; then
    for path in "$rtl"/tb_*.sv; do
        name="$(basename "$path" .sv)"

        if [ "$mode" = --quick ] && in_list "$name" "${slow_tests[@]}"; then
            continue
        fi

        if in_list "$name" "${skipped_tests[@]}"; then
            echo "SKIP $name (input vectors not in repository)"
            continue
        fi

        tests+=("$name")
    done

    for path in "$repo"/tests/rtl/tb_*.sv; do
        [ -e "$path" ] || continue

        name="$(basename "$path" .sv)"

        in_tests_rtl "$name" || {
            echo "SKIP $name (no source list in tests_rtl_sources)"
            continue
        }

        tests+=("$name")
    done
fi

mkdir -p "$build"

passed=0
failed=0
failures=()

for name in "${tests[@]}"; do
    if in_tests_rtl "$name"; then
        source="$repo/tests/rtl/$name.sv"
    else
        source="$rtl/$name.sv"
    fi

    if [ ! -f "$source" ]; then
        echo "FAIL $name (no such testbench)"
        failed=$((failed + 1))
        failures+=("$name")
        continue
    fi

    log="$build/$name.log"

    extra_defines=()
    extra_sources=()

    if in_list "$name" "${fast_modmul_tests[@]}"; then
        extra_defines=(-DFAST_MODMUL)
        extra_sources=("$rtl/modmul_core_fast_sim.sv")
    fi

    if in_tests_rtl "$name"; then
        vector_root="$repo/${tests_rtl_vectors[$name]}"

        if ! compgen -G "$vector_root/*.hex" >/dev/null; then
            echo "SKIP $name (no vectors in ${tests_rtl_vectors[$name]})"
            continue
        fi

        sources=()
        for relative in ${tests_rtl_sources[$name]}; do
            sources+=("$repo/$relative")
        done

        log="$build/$name.log"

        if ! iverilog -g2012 -s "$name" \
            -o "$build/$name" \
            "${sources[@]}" \
            "$source" \
            2> "$log"
        then
            echo "FAIL $name (compile)"
            sed 's/^/    /' "$log"
            failed=$((failed + 1))
            failures+=("$name")
            continue
        fi

        started=$(date +%s)

        timeout "$per_test_timeout" vvp "$build/$name" \
            "+VECTOR_ROOT=$vector_root" \
            > "$log" 2>&1
        status=$?

        elapsed=$(( $(date +%s) - started ))

        if [ $status -eq 124 ]; then
            echo "FAIL $name (timeout after ${per_test_timeout}s)"
            failed=$((failed + 1))
            failures+=("$name")
        elif [ $status -ne 0 ] || grep -q "FAIL" "$log"; then
            echo "FAIL $name (${elapsed}s)"
            tail -n 20 "$log" | sed 's/^/    /'
            failed=$((failed + 1))
            failures+=("$name")
        else
            echo "PASS $name (${elapsed}s)"
            passed=$((passed + 1))
        fi

        continue
    fi

    if ! iverilog -g2012 -Y .sv -y "$rtl" \
        "${extra_defines[@]}" \
        -o "$build/$name" \
        "${packages[@]}" \
        "${extra_sources[@]}" \
        "$source" \
        2> "$log"
    then
        echo "FAIL $name (compile)"
        sed 's/^/    /' "$log"
        failed=$((failed + 1))
        failures+=("$name")
        continue
    fi

    started=$(date +%s)

    # Testbenches load golden vectors through paths relative to rtl/.
    (cd "$rtl" && timeout "$per_test_timeout" vvp "$build/$name") \
        > "$log" 2>&1
    status=$?

    elapsed=$(( $(date +%s) - started ))

    if [ $status -eq 124 ]; then
        echo "FAIL $name (timeout after ${per_test_timeout}s)"
        failed=$((failed + 1))
        failures+=("$name")
    elif [ $status -ne 0 ] || grep -q "FAIL" "$log"; then
        echo "FAIL $name (${elapsed}s)"
        tail -n 20 "$log" | sed 's/^/    /'
        failed=$((failed + 1))
        failures+=("$name")
    else
        echo "PASS $name (${elapsed}s)"
        passed=$((passed + 1))
    fi
done

echo
echo "passed: $passed  failed: $failed"

if [ $failed -ne 0 ]; then
    printf 'failed test: %s\n' "${failures[@]}"
    exit 1
fi
