# OOC timing sweep for the exact persistent-output multi-pair OpenFHE BV
# session wrapper and its 160-DSP drain-overlap arithmetic child.
#
# Synthesizes once, then implements five proven Vivado 2024.1 strategy
# combinations from the same post-synthesis checkpoint.

if {[llength $argv] != 2} {
    puts stderr \
        "usage: build_bv_keyreuse_multi_pair_session_ooc_timing_sweep.tcl REPO_ROOT BUILD_ROOT"

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
set top "evalmul3_bv_keyreuse_multi_pair_session_axis_core"
set expected_dsp_count 160

file mkdir $build_root

set summary_file [
    open \
        [file join \
            $build_root \
            "build_summary.txt"] \
        "w"
]

proc summary_puts {channel text} {
    puts $text
    puts $channel $text
    flush $channel
}

proc run_opt {directive} {
    if {$directive eq "Default"} {
        opt_design
    } else {
        opt_design \
            -directive $directive
    }
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

proc failing_count {} {
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
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_TIMING_SWEEP_BEGIN"

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
    "clock_period_ns=10.000"

summary_puts \
    $summary_file \
    "clock_uncertainty_ns=0.154"

summary_puts \
    $summary_file \
    "expected_dsp48e1=$expected_dsp_count"

summary_puts \
    $summary_file \
    "hd_clk_src=BUFGCTRL_X0Y17"

summary_puts \
    $summary_file \
    "max_pair_count=6"

summary_puts \
    $summary_file \
    "persistent_output_session=1"

summary_puts \
    $summary_file \
    "intermediate_tlast_suppression=1"

summary_puts \
    $summary_file \
    "registered_payload_fifo_depth=2"

set_param \
    general.maxThreads \
    1

foreach rtl_file [list \
    [file join \
        $repo_root \
        rtl \
        modmul_barrett60_pipeline_split_core.sv] \
    [file join \
        $repo_root \
        rtl \
        evalmul3_bv_keyreuse_drain_overlap_axis_core.sv] \
    [file join \
        $repo_root \
        rtl \
        evalmul3_bv_keyreuse_multi_pair_session_axis_core.sv]] {
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
    -period 10.000 \
    [get_ports clk]

set_property \
    HD.CLK_SRC \
    BUFGCTRL_X0Y17 \
    [get_ports clk]

set_clock_uncertainty \
    0.154 \
    [get_clocks core_clk]

set_false_path \
    -from [get_ports reset_n]

set post_synth [
    file join \
        $build_root \
        "post_synth.dcp"
]

write_checkpoint \
    -force \
    $post_synth

report_utilization \
    -hierarchical \
    -file [file join \
        $build_root \
        "post_synth_utilization.rpt"]

set synth_dsp [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == DSP48E1}
    ]
]

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_SYNTH_DSP48E1=$synth_dsp"

if {$synth_dsp != $expected_dsp_count} {
    summary_puts \
        $summary_file \
        "FAIL: synthesis did not preserve exactly 160 DSP48E1"

    close $summary_file
    exit 4
}

close_design

# name, opt, place, pre-route phys_opt, route, post-route phys_opt
set strategies [list \
    [list \
        ExploreWithRemap \
        ExploreWithRemap \
        Explore \
        Explore \
        NoTimingRelaxation \
        Explore] \
    [list \
        RemapNetDelayHigh \
        ExploreWithRemap \
        ExtraNetDelay_high \
        AggressiveExplore \
        NoTimingRelaxation \
        AggressiveExplore] \
    [list \
        DefaultExplore \
        Default \
        Explore \
        AggressiveExplore \
        NoTimingRelaxation \
        AggressiveExplore] \
    [list \
        ExplorePostRoutePhysOpt \
        Explore \
        Explore \
        Explore \
        Explore \
        Explore] \
    [list \
        ExploreNetDelayHigh \
        Explore \
        ExtraNetDelay_high \
        AggressiveExplore \
        NoTimingRelaxation \
        AggressiveExplore] \
]

set best_wns -999.000
set best_failing 1000000
set best_strategy ""
set best_stage ""

set best_checkpoint [
    file join \
        $build_root \
        "best_routed.dcp"
]

foreach strategy $strategies {
    lassign \
        $strategy \
        name \
        opt \
        place \
        pre_phys \
        route \
        post_phys

    set strategy_dir [
        file join \
            $build_root \
            $name
    ]

    file mkdir \
        $strategy_dir

    summary_puts \
        $summary_file \
        "STRATEGY_BEGIN=$name"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_OPT=$opt"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_PLACE=$place"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_PRE_PHYS=$pre_phys"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_ROUTE=$route"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_POST_PHYS=$post_phys"

    open_checkpoint \
        $post_synth

    run_opt \
        $opt

    place_design \
        -directive $place

    phys_opt_design \
        -directive $pre_phys

    route_design \
        -directive $route

    set route_dcp [
        file join \
            $strategy_dir \
            "routed_before_post_phys.dcp"
    ]

    write_checkpoint \
        -force \
        $route_dcp

    set route_wns [
        current_wns
    ]

    set route_failing [
        failing_count
    ]

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_ROUTE_WNS_NS=$route_wns"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_ROUTE_FAILING_PATHS=$route_failing"

    report_timing_summary \
        -delay_type max \
        -max_paths 100 \
        -file [file join \
            $strategy_dir \
            "route_timing_summary.rpt"]

    report_timing \
        -delay_type max \
        -max_paths 100 \
        -path_type full_clock_expanded \
        -file [file join \
            $strategy_dir \
            "route_critical_paths.rpt"]

    if {$route_wns > $best_wns} {
        set best_wns \
            $route_wns

        set best_failing \
            $route_failing

        set best_strategy \
            $name

        set best_stage \
            "route"

        file copy \
            -force \
            $route_dcp \
            $best_checkpoint
    }

    # Vivado 2024.1 infers post-route operation from the routed state.
    phys_opt_design \
        -directive $post_phys

    set post_dcp [
        file join \
            $strategy_dir \
            "routed_after_post_phys.dcp"
    ]

    write_checkpoint \
        -force \
        $post_dcp

    set post_wns [
        current_wns
    ]

    set post_failing [
        failing_count
    ]

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_POST_PHYS_WNS_NS=$post_wns"

    summary_puts \
        $summary_file \
        "STRATEGY_${name}_POST_PHYS_FAILING_PATHS=$post_failing"

    report_timing_summary \
        -delay_type max \
        -max_paths 100 \
        -file [file join \
            $strategy_dir \
            "post_phys_timing_summary.rpt"]

    report_timing \
        -delay_type max \
        -max_paths 100 \
        -path_type full_clock_expanded \
        -file [file join \
            $strategy_dir \
            "post_phys_critical_paths.rpt"]

    report_utilization \
        -hierarchical \
        -file [file join \
            $strategy_dir \
            "post_phys_utilization.rpt"]

    if {$post_wns > $best_wns} {
        set best_wns \
            $post_wns

        set best_failing \
            $post_failing

        set best_strategy \
            $name

        set best_stage \
            "post_phys"

        file copy \
            -force \
            $post_dcp \
            $best_checkpoint
    }

    summary_puts \
        $summary_file \
        "STRATEGY_END=$name"

    close_design
}

open_checkpoint \
    $best_checkpoint

set dsp [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == DSP48E1}
    ]
]

set luts [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ LUT*}
    ]
]

set regs [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ FD*}
    ]
]

set ram18 [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == RAMB18E1}
    ]
]

set ram36 [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == RAMB36E1}
    ]
]

set srl [
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
    -max_paths 100 \
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
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_BEST_STRATEGY=$best_strategy"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_BEST_STAGE=$best_stage"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_WNS_NS=$best_wns"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_FAILING_PATHS=$best_failing"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_LUTS=$luts"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_REGISTERS=$regs"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_DSP48E1=$dsp"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_RAMB18E1=$ram18"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_RAMB36E1=$ram36"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_SRL=$srl"

summary_puts \
    $summary_file \
    "best_checkpoint=$best_checkpoint"

if {$dsp != $expected_dsp_count} {
    summary_puts \
        $summary_file \
        "FAIL: best multi-pair session implementation does not contain exactly 160 DSP48E1"

    close $summary_file
    exit 5
}

if {$best_wns < 0.000} {
    summary_puts \
        $summary_file \
        "FAIL: all multi-pair session timing strategies missed 100 MHz"

    close $summary_file
    exit 6
}

summary_puts \
    $summary_file \
    "PASS: persistent-output multi-pair session core routed at 100 MHz"

summary_puts \
    $summary_file \
    "BV_KEYREUSE_MULTI_PAIR_SESSION_OOC_TIMING_SWEEP_END"

close $summary_file
exit 0
