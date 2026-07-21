set source_root F:/repos/pynq_butterfly
set rtl_dir [file join $source_root rtl]

set report_dir \
    [file join \
        $source_root \
        reports \
        modmul_barrett60_pipeline_split_implemented \
    ]

set part_name xc7z020clg400-1
set top_name modmul_barrett60_pipeline_split_core
set clock_period_ns 10.000

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

proc count_cells {filter_expression} {
    return [llength \
        [get_cells \
            -hierarchical \
            -quiet \
            -filter $filter_expression \
        ] \
    ]
}

file delete -force $report_dir
file mkdir $report_dir

set rtl_file \
    [file join \
        $rtl_dir \
        modmul_barrett60_pipeline_split_core.sv \
    ]

require_file $rtl_file
read_verilog -sv $rtl_file

synth_design \
    -top $top_name \
    -part $part_name \
    -flatten_hierarchy rebuilt \
    -mode out_of_context

create_clock \
    -name clk \
    -period $clock_period_ns \
    [get_ports clk]

set data_inputs \
    [get_ports \
        -quiet \
        -filter {DIRECTION == IN && NAME != clk} \
    ]

set data_outputs \
    [get_ports \
        -quiet \
        -filter {DIRECTION == OUT} \
    ]

set_input_delay \
    0.000 \
    -clock clk \
    $data_inputs

set_output_delay \
    0.000 \
    -clock clk \
    $data_outputs

opt_design
place_design
phys_opt_design
route_design
phys_opt_design

set checkpoint_file \
    [file join $report_dir routed.dcp]

set utilization_report \
    [file join $report_dir utilization.rpt]

set timing_report \
    [file join $report_dir timing_summary.rpt]

set check_timing_report \
    [file join $report_dir check_timing.rpt]

write_checkpoint \
    -force \
    $checkpoint_file

check_timing \
    -verbose \
    -file $check_timing_report

report_utilization \
    -file $utilization_report

report_timing_summary \
    -delay_type max \
    -max_paths 50 \
    -file $timing_report

set worst_path \
    [lindex \
        [get_timing_paths \
            -quiet \
            -delay_type max \
            -max_paths 1 \
        ] \
        0 \
    ]

if {$worst_path eq ""} {
    set wns_ns UNAVAILABLE
    set datapath_ns UNAVAILABLE
    set logic_levels UNAVAILABLE
    set startpoint UNAVAILABLE
    set endpoint UNAVAILABLE
} else {
    set wns_ns \
        [get_property SLACK $worst_path]

    set datapath_ns \
        [get_property DATAPATH_DELAY $worst_path]

    set logic_levels \
        [get_property LOGIC_LEVELS $worst_path]

    set startpoint \
        [get_property STARTPOINT_PIN $worst_path]

    set endpoint \
        [get_property ENDPOINT_PIN $worst_path]
}

set lut_count \
    [count_cells {REF_NAME =~ LUT*}]

set register_count \
    [count_cells {REF_NAME =~ FD*}]

set carry4_count \
    [count_cells {REF_NAME == CARRY4}]

set dsp_count \
    [count_cells {REF_NAME == DSP48E1}]

set ramb18_count \
    [count_cells {REF_NAME == RAMB18E1}]

set ramb36_count \
    [count_cells {REF_NAME == RAMB36E1}]

set summary_file \
    [file join $report_dir implementation_summary.txt]

set fh [open $summary_file w]

puts $fh "top=$top_name"
puts $fh "part=$part_name"
puts $fh "clock_period_ns=$clock_period_ns"
puts $fh "implementation_status=Complete"
puts $fh "pipeline_latency=7"
puts $fh "initiation_interval=1"
puts $fh "lut=$lut_count"
puts $fh "registers=$register_count"
puts $fh "carry4=$carry4_count"
puts $fh "dsp=$dsp_count"
puts $fh "ramb18=$ramb18_count"
puts $fh "ramb36=$ramb36_count"
puts $fh "wns_ns=$wns_ns"
puts $fh "datapath_ns=$datapath_ns"
puts $fh "logic_levels=$logic_levels"
puts $fh "startpoint=$startpoint"
puts $fh "endpoint=$endpoint"
puts $fh "checkpoint=[file normalize $checkpoint_file]"
puts $fh "utilization_report=[file normalize $utilization_report]"
puts $fh "timing_report=[file normalize $timing_report]"
puts $fh "check_timing_report=[file normalize $check_timing_report]"

close $fh

puts ""
puts "============================================================"
puts "SPLIT BARRETT PIPELINE IMPLEMENTATION COMPLETE"
puts "============================================================"
puts "LUTs:             $lut_count"
puts "Registers:        $register_count"
puts "CARRY4:           $carry4_count"
puts "DSP48E1:          $dsp_count"
puts "RAMB18E1:         $ramb18_count"
puts "RAMB36E1:         $ramb36_count"
puts "WNS:              $wns_ns ns"
puts "Datapath:         $datapath_ns ns"
puts "Logic levels:     $logic_levels"
puts "Startpoint:       $startpoint"
puts "Endpoint:         $endpoint"
puts "Summary:          [file normalize $summary_file]"
puts "============================================================"
puts ""
