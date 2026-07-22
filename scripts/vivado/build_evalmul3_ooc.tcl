# Out-of-context physical implementation for the fused two-tower
# evaluation-domain ciphertext core.
#
# Usage:
#   vivado -mode batch -source build_evalmul3_ooc.tcl \
#     -tclargs REPO_ROOT BUILD_DIR

if {[llength $argv] != 2} {
    puts stderr "usage: build_evalmul3_ooc.tcl REPO_ROOT BUILD_DIR"
    exit 2
}

set repo_root [file normalize [lindex $argv 0]]
set build_dir [file normalize [lindex $argv 1]]

set part "xc7z020clg400-1"
set top "evalmul3_two_tower_axis_core"
set clock_period_ns 10.000

file mkdir $build_dir

set log_path [file join $build_dir "build_summary.txt"]
set log_file [open $log_path "w"]

proc summary_puts {channel text} {
    puts $text
    puts $channel $text
    flush $channel
}

summary_puts $log_file "EVALMUL3_OOC_BEGIN"
summary_puts $log_file "repo_root=$repo_root"
summary_puts $log_file "build_dir=$build_dir"
summary_puts $log_file "part=$part"
summary_puts $log_file "top=$top"
summary_puts $log_file "clock_period_ns=$clock_period_ns"

set_param general.maxThreads 1

set rtl_files [list \
    [file join \
        $repo_root \
        "rtl" \
        "modmul_barrett60_pipeline_split_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "evalmul3_two_tower_axis_core.sv"] \
]

foreach rtl_file $rtl_files {
    if {![file isfile $rtl_file]} {
        summary_puts $log_file "ERROR: missing RTL file: $rtl_file"
        close $log_file
        exit 2
    }

    read_verilog -sv $rtl_file
}

synth_design \
    -top $top \
    -part $part \
    -mode out_of_context \
    -flatten_hierarchy rebuilt \
    -verilog_define SYNTHESIS

create_clock \
    -name axis_clk \
    -period $clock_period_ns \
    [get_ports clk]

set nonclock_inputs [
    get_ports -quiet -filter {
        DIRECTION == IN && NAME != clk
    }
]

set output_ports [
    get_ports -quiet -filter {
        DIRECTION == OUT
    }
]

if {[llength $nonclock_inputs] != 0} {
    set_input_delay \
        -clock axis_clk \
        0.000 \
        $nonclock_inputs
}

if {[llength $output_ports] != 0} {
    set_output_delay \
        -clock axis_clk \
        0.000 \
        $output_ports
}

set_false_path \
    -from [get_ports reset_n]

report_utilization \
    -hierarchical \
    -file [file join $build_dir "synth_utilization.rpt"]

report_timing_summary \
    -delay_type max \
    -max_paths 20 \
    -file [file join $build_dir "synth_timing_summary.rpt"]

write_checkpoint \
    -force \
    [file join $build_dir "synth.dcp"]

opt_design

place_design \
    -directive Explore

phys_opt_design \
    -directive Explore

write_checkpoint \
    -force \
    [file join $build_dir "placed.dcp"]

route_design \
    -directive NoTimingRelaxation

# Vivado 2024.1 infers post-route mode from the current routed design.
# The phys_opt_design command has no explicit post-route switch.
#
# Preserve the raw routed result before optional physical optimization so
# a later failure cannot discard a successful route.
write_checkpoint \
    -force \
    [file join $build_dir "routed_before_physopt.dcp"]

phys_opt_design \
    -directive Explore

write_checkpoint \
    -force \
    [file join $build_dir "routed.dcp"]

report_drc \
    -file [file join $build_dir "drc.rpt"]

report_utilization \
    -hierarchical \
    -file [file join $build_dir "routed_utilization.rpt"]

report_timing_summary \
    -delay_type max \
    -max_paths 50 \
    -file [file join $build_dir "routed_timing_summary.rpt"]

report_timing \
    -delay_type max \
    -max_paths 20 \
    -path_type full_clock_expanded \
    -file [file join $build_dir "routed_critical_paths.rpt"]

report_clock_utilization \
    -file [file join $build_dir "clock_utilization.rpt"]

set timing_paths [
    get_timing_paths \
        -quiet \
        -delay_type max \
        -max_paths 1 \
        -nworst 1
]

if {[llength $timing_paths] == 0} {
    summary_puts $log_file "ERROR: no routed timing path was returned"
    close $log_file
    exit 2
}

set worst_path [lindex $timing_paths 0]
set wns [get_property SLACK $worst_path]

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

summary_puts $log_file "EVALMUL3_OOC_WNS_NS=$wns"
summary_puts $log_file "EVALMUL3_OOC_FAILING_PATHS=[llength $failing_paths]"
summary_puts $log_file "EVALMUL3_OOC_LUTS=$lut_count"
summary_puts $log_file "EVALMUL3_OOC_REGISTERS=$register_count"
summary_puts $log_file "EVALMUL3_OOC_DSP48E1=$dsp_count"
summary_puts $log_file "EVALMUL3_OOC_RAMB18E1=$ramb18_count"
summary_puts $log_file "EVALMUL3_OOC_RAMB36E1=$ramb36_count"

if {$dsp_count > 220} {
    summary_puts $log_file \
        "ERROR: DSP usage exceeds the XC7Z020 total of 220"
    close $log_file
    exit 3
}

if {$wns < 0.000} {
    summary_puts $log_file \
        "FAIL: fused evaluation-domain core missed 100 MHz"
    close $log_file
    exit 4
}

summary_puts $log_file \
    "PASS: fused evaluation-domain core routed at 100 MHz"

summary_puts $log_file \
    "EVALMUL3_OOC_END"

close $log_file
exit 0
