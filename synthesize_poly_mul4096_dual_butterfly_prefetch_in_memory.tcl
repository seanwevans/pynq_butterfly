set root_dir F:/repos/pynq_butterfly
set rtl_dir [file join $root_dir rtl]
set report_dir [file join $root_dir reports poly_mul4096_dual_butterfly_prefetch_in_memory]
set top_name poly_mul4096_dual_butterfly_two_tower_prefetch_axis_core
set part_name xc7z020clg400-1
set clock_period_ns 10.000

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

proc count_cells {filter_expression} {
    return [llength [get_cells -hierarchical -quiet -filter $filter_expression]]
}

file delete -force $report_dir
file mkdir $report_dir

set rtl_files [list \
    [file join $rtl_dir modmul_core.sv] \
    [file join $rtl_dir ntt4096_coeff_bank_1024x32.sv] \
    [file join $rtl_dir ntt4096_four_bank_coeff_store.sv] \
    [file join $rtl_dir ntt4096_profile_bram_dual_read.sv] \
    [file join $rtl_dir ntt4096_paired_schedule_core.sv] \
    [file join $rtl_dir ntt4096_dual_mode_butterfly_core.sv] \
    [file join $rtl_dir poly_mul4096_dual_butterfly_runtime_profile_core.sv] \
    [file join $rtl_dir poly_mul4096_dual_butterfly_runtime_profile_prefetch_axis_core.sv] \
    [file join $rtl_dir poly_mul4096_dual_butterfly_two_tower_prefetch_axis_core.sv] \
]

foreach path $rtl_files {
    require_file $path
}

create_project -in_memory -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

foreach path $rtl_files {
    read_verilog -sv $path
}

synth_design \
    -top $top_name \
    -part $part_name \
    -flatten_hierarchy rebuilt \
    -directive PerformanceOptimized

create_clock -name clk -period $clock_period_ns [get_ports clk]

set utilization_report [file join $report_dir utilization.rpt]
set hierarchy_report [file join $report_dir hierarchical_utilization.rpt]
set timing_report [file join $report_dir timing_summary.rpt]

report_utilization -file $utilization_report
report_utilization -hierarchical -hierarchical_depth 20 -file $hierarchy_report
report_timing_summary -delay_type max -max_paths 50 -file $timing_report

set lut_count [count_cells {REF_NAME =~ LUT*}]
set register_count [count_cells {REF_NAME =~ FD*}]
set carry4_count [count_cells {REF_NAME == CARRY4}]
set dsp_count [count_cells {REF_NAME == DSP48E1}]
set ramb18_count [count_cells {REF_NAME == RAMB18E1}]
set ramb36_count [count_cells {REF_NAME == RAMB36E1}]
set bram_tile_equivalent [expr {$ramb36_count + ($ramb18_count / 2.0)}]

set worst_path [lindex [get_timing_paths -quiet -delay_type max -from [all_registers] -to [all_registers] -max_paths 1] 0]

if {$worst_path eq ""} {
    set wns_ns NA
    set datapath_ns NA
    set logic_levels NA
    set startpoint NA
    set endpoint NA
} else {
    set wns_ns [get_property SLACK $worst_path]
    set datapath_ns [get_property DATAPATH_DELAY $worst_path]
    set logic_levels [get_property LOGIC_LEVELS $worst_path]
    set startpoint [get_property STARTPOINT_PIN $worst_path]
    set endpoint [get_property ENDPOINT_PIN $worst_path]
}

set summary_file [file join $report_dir synthesis_summary.txt]
set fh [open $summary_file w]
puts $fh "mode=in_memory"
puts $fh "top=$top_name"
puts $fh "part=$part_name"
puts $fh "clock_period_ns=$clock_period_ns"
puts $fh "synthesis_status=Complete"
puts $fh "prefetch_depth_products=1"
puts $fh "same_address_read_then_write_refill=true"
puts $fh "arithmetic_fsm_changed=false"
puts $fh "per_product_core_cycles=631810"
puts $fh "transition_cycles_per_nonfinal_product=8193"
puts $fh "expected_shadow_ramb36=16"
puts $fh "expected_total_ramb36=64"
puts $fh "tower_lanes=2"
puts $fh "total_modmul_lanes=24"
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
puts $fh "hierarchical_report=[file normalize $hierarchy_report]"
puts $fh "timing_report=[file normalize $timing_report]"
close $fh

puts ""
puts "============================================================"
puts "PREFETCH TWO-TOWER IN-MEMORY SYNTHESIS COMPLETE"
puts "============================================================"
puts "LUTs:                  $lut_count"
puts "Registers:             $register_count"
puts "CARRY4:                $carry4_count"
puts "DSP48E1:               $dsp_count"
puts "RAMB18E1:              $ramb18_count"
puts "RAMB36E1:              $ramb36_count"
puts "WNS:                   $wns_ns ns"
puts "Datapath delay:        $datapath_ns ns"
puts "Logic levels:          $logic_levels"
puts "Startpoint:            $startpoint"
puts "Endpoint:              $endpoint"
puts "Expected RAMB36:       64"
puts "Core cycles/product:   631810"
puts "Summary:               $summary_file"
puts "============================================================"
puts ""

close_project
