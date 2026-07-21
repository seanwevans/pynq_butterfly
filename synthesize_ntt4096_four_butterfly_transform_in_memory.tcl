set source_root F:/repos/pynq_butterfly
set rtl_dir [file join $source_root rtl]

set report_dir \
    [file join \
        $source_root \
        reports \
        ntt4096_four_butterfly_transform_in_memory \
    ]

set part_name xc7z020clg400-1
set top_name ntt4096_four_butterfly_transform_synthesis_top
set clock_period_ns 10.000
set input_delay_ns 0.000
set output_delay_ns 0.000

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
        ]
    ]
}

file delete -force $report_dir
file mkdir $report_dir

set rtl_files [list \
    [file join $rtl_dir modmul_core.sv] \
    [file join $rtl_dir ntt4096_dual_mode_butterfly_core.sv] \
    [file join $rtl_dir ntt4096_profile_bram_dual_read.sv] \
    [file join $rtl_dir ntt4096_coeff_bank_512x32.sv] \
    [file join $rtl_dir ntt4096_four_butterfly_schedule_core.sv] \
    [file join $rtl_dir ntt4096_profile_bram_four_read.sv] \
    [file join $rtl_dir ntt4096_eight_bank_coeff_store_runtime.sv] \
    [file join $rtl_dir ntt4096_four_butterfly_transform_core.sv] \
    [file join $rtl_dir ntt4096_four_butterfly_transform_synthesis_top.sv] \
]

foreach path $rtl_files {
    require_file $path
    read_verilog -sv $path
}

synth_design \
    -top $top_name \
    -part $part_name \
    -flatten_hierarchy rebuilt

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
    $input_delay_ns \
    -clock clk \
    $data_inputs

set_output_delay \
    $output_delay_ns \
    -clock clk \
    $data_outputs

set utilization_report \
    [file join $report_dir utilization.rpt]

set hierarchical_report \
    [file join $report_dir hierarchical_utilization.rpt]

set timing_report \
    [file join $report_dir timing_summary.rpt]

set check_timing_report \
    [file join $report_dir check_timing.rpt]

check_timing \
    -verbose \
    -file $check_timing_report

report_utilization \
    -file $utilization_report

report_utilization \
    -hierarchical \
    -file $hierarchical_report

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
    set wns_ns [get_property SLACK $worst_path]
    set datapath_ns [get_property DATAPATH_DELAY $worst_path]
    set logic_levels [get_property LOGIC_LEVELS $worst_path]
    set startpoint [get_property STARTPOINT_PIN $worst_path]
    set endpoint [get_property ENDPOINT_PIN $worst_path]
}

set lut_count [count_cells {REF_NAME =~ LUT*}]
set register_count [count_cells {REF_NAME =~ FD*}]
set carry4_count [count_cells {REF_NAME == CARRY4}]
set dsp_count [count_cells {REF_NAME == DSP48E1}]
set ramb18_count [count_cells {REF_NAME == RAMB18E1}]
set ramb36_count [count_cells {REF_NAME == RAMB36E1}]

set bram_tile_equivalent \
    [expr {$ramb36_count + ($ramb18_count / 2.0)}]

set summary_file \
    [file join $report_dir synthesis_summary.txt]

set fh [open $summary_file w]

puts $fh "mode=in_memory"
puts $fh "top=$top_name"
puts $fh "part=$part_name"
puts $fh "clock_period_ns=$clock_period_ns"
puts $fh "input_delay_ns=$input_delay_ns"
puts $fh "output_delay_ns=$output_delay_ns"
puts $fh "registered_synthesis_shell=true"
puts $fh "synthesis_status=Complete"
puts $fh "n=4096"
puts $fh "butterflies_per_group=4"
puts $fh "coefficients_per_group=8"
puts $fh "groups_per_stage=512"
puts $fh "stages_per_transform=12"
puts $fh "groups_per_transform=6144"
puts $fh "modmul_lanes=4"
puts $fh "transform_cycles=141313"
puts $fh "butterflies_per_transform=24576"
puts $fh "coefficient_bank_count=8"
puts $fh "twiddle_read_ports=4"
puts $fh "expected_coefficient_ramb18=8"
puts $fh "expected_twiddle_ramb36=8"
puts $fh "lut=$lut_count"
puts $fh "registers=$register_count"
puts $fh "carry4=$carry4_count"
puts $fh "dsp=$dsp_count"
puts $fh "ramb18=$ramb18_count"
puts $fh "ramb36=$ramb36_count"
puts $fh "bram_tile_equivalent=$bram_tile_equivalent"
puts $fh "wns_ns=$wns_ns"
puts $fh "datapath_ns=$datapath_ns"
puts $fh "logic_levels=$logic_levels"
puts $fh "startpoint=$startpoint"
puts $fh "endpoint=$endpoint"
puts $fh "utilization_report=[file normalize $utilization_report]"
puts $fh "hierarchical_report=[file normalize $hierarchical_report]"
puts $fh "timing_report=[file normalize $timing_report]"
puts $fh "check_timing_report=[file normalize $check_timing_report]"

close $fh

puts ""
puts "============================================================"
puts "FOUR-BUTTERFLY NTT SYNTHESIS COMPLETE"
puts "============================================================"
puts "LUTs:                    $lut_count"
puts "Registers:               $register_count"
puts "CARRY4:                  $carry4_count"
puts "DSP48E1:                 $dsp_count"
puts "RAMB18E1:                $ramb18_count"
puts "RAMB36E1:                $ramb36_count"
puts "BRAM tile equivalent:    $bram_tile_equivalent"
puts "WNS:                     $wns_ns ns"
puts "Transform cycles:        141313"
puts "Summary:                 [file normalize $summary_file]"
puts "============================================================"
puts ""
