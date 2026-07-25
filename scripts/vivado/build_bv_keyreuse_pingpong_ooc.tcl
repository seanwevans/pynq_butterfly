# Out-of-context physical implementation of the exact ping-pong
# coefficient-major OpenFHE BV evaluation-key-reuse core.
#
# Usage:
#   vivado -mode batch \
#     -source build_bv_keyreuse_pingpong_ooc.tcl \
#     -tclargs REPO_ROOT BUILD_ROOT

if {[llength $argv] != 2} {
    puts stderr \
        "usage: build_bv_keyreuse_pingpong_ooc.tcl REPO_ROOT BUILD_ROOT"

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
set top "evalmul3_bv_keyreuse_pingpong_axis_core"
set clock_period_ns 10.000
set clock_uncertainty_ns 0.154
set expected_dsp_count 160

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

proc current_wns {} {
    set paths [
        get_timing_paths \
            -quiet \
            -delay_type max \
            -max_paths 1 \
            -nworst 1
    ]

    if {[llength $paths] == 0} {
        return -999.000
    }

    return [
        get_property \
            SLACK \
            [lindex $paths 0]
    ]
}

proc current_failing_paths {} {
    return [
        llength [
            get_timing_paths \
                -quiet \
                -delay_type max \
                -slack_lesser_than 0.000 \
                -max_paths 100000
        ]
    ]
}

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_BUILD_BEGIN"

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
    "max_batch=64"

summary_puts \
    $summary_file \
    "minimum_batch=8"

summary_puts \
    $summary_file \
    "coefficient_banks=2"

summary_puts \
    $summary_file \
    "implementation_strategy=NetDelayHigh"

summary_puts \
    $summary_file \
    "opt_directive=Default"

summary_puts \
    $summary_file \
    "place_directive=ExtraNetDelay_high"

summary_puts \
    $summary_file \
    "pre_route_phys_opt_directive=AggressiveExplore"

summary_puts \
    $summary_file \
    "route_directive=NoTimingRelaxation"

summary_puts \
    $summary_file \
    "post_route_phys_opt_directive=AggressiveExplore"

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
        "evalmul3_bv_keyreuse_pingpong_axis_core.sv"] \
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
    -flatten_hierarchy rebuilt

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

set post_synth_dcp [
    file join \
        $build_root \
        "post_synth.dcp"
]

write_checkpoint \
    -force \
    $post_synth_dcp

report_utilization \
    -hierarchical \
    -file [file join \
        $build_root \
        "post_synth_utilization.rpt"]

set synth_dsp_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == DSP48E1}
    ]
]

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_SYNTH_DSP48E1=$synth_dsp_count"

if {$synth_dsp_count != $expected_dsp_count} {
    summary_puts \
        $summary_file \
        "FAIL: synthesis did not preserve exactly 160 DSP48E1"

    close $summary_file
    exit 4
}

opt_design

place_design \
    -directive ExtraNetDelay_high

phys_opt_design \
    -directive AggressiveExplore

route_design \
    -directive NoTimingRelaxation

set route_dcp [
    file join \
        $build_root \
        "routed_before_post_phys.dcp"
]

write_checkpoint \
    -force \
    $route_dcp

set route_wns [
    current_wns
]

set route_failing [
    current_failing_paths
]

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_ROUTE_WNS_NS=$route_wns"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_ROUTE_FAILING_PATHS=$route_failing"

report_timing_summary \
    -delay_type max \
    -max_paths 100 \
    -file [file join \
        $build_root \
        "route_timing_summary.rpt"]

report_timing \
    -delay_type max \
    -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join \
        $build_root \
        "route_critical_paths.rpt"]

# Vivado 2024.1 infers post-route mode from the routed design state.
phys_opt_design \
    -directive AggressiveExplore

set post_phys_dcp [
    file join \
        $build_root \
        "routed_after_post_phys.dcp"
]

write_checkpoint \
    -force \
    $post_phys_dcp

set post_wns [
    current_wns
]

set post_failing [
    current_failing_paths
]

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_POST_PHYS_WNS_NS=$post_wns"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_POST_PHYS_FAILING_PATHS=$post_failing"

report_timing_summary \
    -delay_type max \
    -max_paths 100 \
    -file [file join \
        $build_root \
        "post_phys_timing_summary.rpt"]

report_timing \
    -delay_type max \
    -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join \
        $build_root \
        "post_phys_critical_paths.rpt"]

set best_wns $route_wns
set best_failing $route_failing
set best_stage "route"
set best_source_dcp $route_dcp

if {$post_wns > $best_wns} {
    set best_wns $post_wns
    set best_failing $post_failing
    set best_stage "post_phys"
    set best_source_dcp $post_phys_dcp
}

set best_checkpoint [
    file join \
        $build_root \
        "best_routed.dcp"
]

file copy \
    -force \
    $best_source_dcp \
    $best_checkpoint

open_checkpoint \
    $best_checkpoint

set dsp_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == DSP48E1}
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

set srl_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ SRL*}
    ]
]

report_drc \
    -file [file join \
        $build_root \
        "best_drc.rpt"]

report_timing_summary \
    -delay_type max \
    -max_paths 100 \
    -file [file join \
        $build_root \
        "best_timing_summary.rpt"]

report_timing \
    -delay_type max \
    -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join \
        $build_root \
        "best_critical_paths.rpt"]

report_utilization \
    -hierarchical \
    -file [file join \
        $build_root \
        "best_utilization.rpt"]

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_BEST_STAGE=$best_stage"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_WNS_NS=$best_wns"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_FAILING_PATHS=$best_failing"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_LUTS=$lut_count"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_REGISTERS=$register_count"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_DSP48E1=$dsp_count"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_RAMB18E1=$ramb18_count"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_RAMB36E1=$ramb36_count"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_SRL=$srl_count"

summary_puts \
    $summary_file \
    "best_checkpoint=$best_checkpoint"

if {$dsp_count != $expected_dsp_count} {
    summary_puts \
        $summary_file \
        "FAIL: ping-pong implementation does not contain exactly 160 DSP48E1"

    close $summary_file
    exit 7
}

if {$best_wns < 0.000} {
    summary_puts \
        $summary_file \
        "FAIL: ping-pong coefficient-major core missed 100 MHz"

    close $summary_file
    exit 8
}

summary_puts \
    $summary_file \
    "PASS: ping-pong coefficient-major evaluation-key-reuse core routed at 100 MHz"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_PINGPONG_OOC_BUILD_END"

close $summary_file
exit 0
