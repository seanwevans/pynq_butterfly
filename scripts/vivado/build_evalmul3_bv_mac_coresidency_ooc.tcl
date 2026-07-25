# Out-of-context physical co-residency build for the exact EvalMul3 and
# OpenFHE BV key-switch MAC engines.
#
# Usage:
#   vivado -mode batch -source build_evalmul3_bv_mac_coresidency_ooc.tcl \
#     -tclargs REPO_ROOT BUILD_ROOT

if {[llength $argv] != 2} {
    puts stderr \
        "usage: build_evalmul3_bv_mac_coresidency_ooc.tcl REPO_ROOT BUILD_ROOT"

    exit 2
}

set repo_root [
    file normalize \
        [lindex $argv 0]
]

set build_root [
    file normalize \
        [lindex $argv 1]
]

set part "xc7z020clg400-1"
set top "evalmul3_bv_mac_coresidency_top"
set clock_period_ns 10.000
set clock_uncertainty_ns 0.154
set expected_dsp_count 192

file mkdir $build_root

set summary_path [
    file join \
        $build_root \
        "build_summary.txt"
]

set summary_file [
    open \
        $summary_path \
        "w"
]

proc summary_puts {channel text} {
    puts $text
    puts $channel $text
    flush $channel
}

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_BUILD_BEGIN"

summary_puts \
    $summary_file \
    "repo_root=$repo_root"

summary_puts \
    $summary_file \
    "build_root=$build_root"

summary_puts \
    $summary_file \
    "part=$part"

summary_puts \
    $summary_file \
    "top=$top"

summary_puts \
    $summary_file \
    "clock_period_ns=$clock_period_ns"

summary_puts \
    $summary_file \
    "clock_uncertainty_ns=$clock_uncertainty_ns"

summary_puts \
    $summary_file \
    "expected_dsp48e1=$expected_dsp_count"

summary_puts \
    $summary_file \
    "hd_clk_src=BUFGCTRL_X0Y17"

set_param \
    general.maxThreads \
    1

set rtl_files [list \
    [file join \
        $repo_root \
        "rtl" \
        "modmul_barrett60_pipeline_split_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "evalmul3_two_tower_axis_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "bv_keyswitch_mac_two_tower_axis_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "evalmul3_bv_mac_coresidency_top.sv"] \
]

foreach rtl_file $rtl_files {
    if {![file isfile $rtl_file]} {
        summary_puts \
            $summary_file \
            "ERROR: missing RTL file: $rtl_file"

        close $summary_file
        exit 3
    }

    read_verilog \
        -sv \
        $rtl_file
}

synth_design \
    -top $top \
    -part $part \
    -mode out_of_context \
    -flatten_hierarchy none

create_clock \
    -name core_clk \
    -period $clock_period_ns \
    [get_ports clk]

set_property \
    HD.CLK_SRC \
    BUFGCTRL_X0Y17 \
    [get_ports clk]

set_clock_uncertainty \
    $clock_uncertainty_ns \
    [get_clocks core_clk]

set_false_path \
    -from [get_ports reset_n]

write_checkpoint \
    -force \
    [file join \
        $build_root \
        "post_synth.dcp"]

report_utilization \
    -hierarchical \
    -file [file join \
        $build_root \
        "post_synth_utilization.rpt"]

opt_design \
    -directive ExploreWithRemap

place_design \
    -directive ExtraNetDelay_high

phys_opt_design \
    -directive AggressiveExplore

route_design \
    -directive AggressiveExplore

# Vivado 2024.1 infers post-route operation from the routed design state.
phys_opt_design \
    -directive AggressiveExplore

write_checkpoint \
    -force \
    [file join \
        $build_root \
        "routed.dcp"]

report_drc \
    -file [file join \
        $build_root \
        "drc.rpt"]

report_utilization \
    -hierarchical \
    -file [file join \
        $build_root \
        "routed_utilization.rpt"]

report_timing_summary \
    -delay_type max \
    -max_paths 100 \
    -file [file join \
        $build_root \
        "routed_timing_summary.rpt"]

report_timing \
    -delay_type max \
    -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join \
        $build_root \
        "routed_critical_paths.rpt"]

set timing_paths [
    get_timing_paths \
        -quiet \
        -delay_type max \
        -max_paths 1 \
        -nworst 1
]

if {[llength $timing_paths] == 0} {
    summary_puts \
        $summary_file \
        "ERROR: no routed timing path was returned"

    close $summary_file
    exit 4
}

set worst_path [
    lindex \
        $timing_paths \
        0
]

set wns [
    get_property \
        SLACK \
        $worst_path
]

set failing_paths [
    get_timing_paths \
        -quiet \
        -delay_type max \
        -slack_lesser_than 0.000 \
        -max_paths 100000
]

set dsp_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == DSP48E1}
    ]
]

set ramb18_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == RAMB18E1}
    ]
]

set ramb36_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == RAMB36E1}
    ]
]

set lut_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ LUT*}
    ]
]

set register_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ FD*}
    ]
]

set evalmul_dsp_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {
                REF_NAME == DSP48E1
                && NAME =~ evalmul_engine/*
            }
    ]
]

set bv_dsp_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {
                REF_NAME == DSP48E1
                && NAME =~ bv_mac_engine/*
            }
    ]
]

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_WNS_NS=$wns"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_FAILING_PATHS=[llength $failing_paths]"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_CLOCK=core_clk"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_LUTS=$lut_count"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_REGISTERS=$register_count"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_DSP48E1=$dsp_count"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_EVALMUL_DSP48E1=$evalmul_dsp_count"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_BV_DSP48E1=$bv_dsp_count"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_RAMB18E1=$ramb18_count"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_RAMB36E1=$ramb36_count"

if {$dsp_count != $expected_dsp_count} {
    summary_puts \
        $summary_file \
        "FAIL: expected exactly 192 total DSP48E1"

    close $summary_file
    exit 5
}

if {$evalmul_dsp_count != 128} {
    summary_puts \
        $summary_file \
        "FAIL: expected exactly 128 EvalMul3 DSP48E1"

    close $summary_file
    exit 6
}

if {$bv_dsp_count != 64} {
    summary_puts \
        $summary_file \
        "FAIL: expected exactly 64 BV-MAC DSP48E1"

    close $summary_file
    exit 7
}

if {$wns < 0.000} {
    summary_puts \
        $summary_file \
        "FAIL: 192-DSP arithmetic co-residency missed 100 MHz"

    close $summary_file
    exit 8
}

summary_puts \
    $summary_file \
    "PASS: exact EvalMul3 and BV-MAC arithmetic cores co-routed at 100 MHz"

summary_puts \
    $summary_file \
    "EVALMUL3_BV_MAC_CORESIDENCY_BUILD_END"

close $summary_file
exit 0
