set root_dir [file dirname [file dirname [file dirname [file normalize [info script]]]]]
set rtl_dir [file join $root_dir rtl]

set project_root \
    [file join $root_dir vivado poly_mul4096_two_tower_parallel_synth]

set report_dir \
    [file join $root_dir reports poly_mul4096_two_tower_parallel_synth]

set project_name poly_mul4096_two_tower_parallel_synth
set top_name poly_mul4096_runtime_profile_dual_axis_core
set part_name xc7z020clg400-1
set clock_period_ns 10.000

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

proc count_cells {filter_expression} {
    return [llength \
        [get_cells -hierarchical -quiet -filter $filter_expression]
    ]
}

file delete -force $project_root
file delete -force $report_dir

file mkdir $project_root
file mkdir $report_dir

set rtl_files [list \
    [file join $rtl_dir ntt4096_profile_pkg.sv] \
    [file join $rtl_dir modmul_core.sv] \
    [file join $rtl_dir butterfly_core.sv] \
    [file join $rtl_dir butterfly_dif_core.sv] \
    [file join $rtl_dir ntt4096_schedule_core.sv] \
    [file join $rtl_dir ntt4096_dif_schedule_core.sv] \
    [file join $rtl_dir ntt4096_coeff_bram.sv] \
    [file join $rtl_dir ntt4096_profile_bram.sv] \
    [file join $rtl_dir poly_mul4096_runtime_profile_core.sv] \
    [file join $rtl_dir poly_mul4096_runtime_profile_axis_core.sv] \
    [file join $rtl_dir poly_mul4096_runtime_profile_dual_axis_core.sv] \
]

foreach path $rtl_files {
    require_file $path
}

create_project \
    -force \
    $project_name \
    $project_root \
    -part $part_name

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files \
    -norecurse \
    $rtl_files

foreach path $rtl_files {
    set_property \
        file_type \
        SystemVerilog \
        [get_files [file normalize $path]]
}

set_property \
    top \
    $top_name \
    [get_filesets sources_1]

set xdc_file \
    [file join $project_root poly_mul4096_two_tower_parallel_synth.xdc]

set fh [open $xdc_file w]

puts $fh [format \
    {create_clock -name clk -period %.3f [get_ports clk]} \
    $clock_period_ns]

close $fh

add_files \
    -fileset constrs_1 \
    -norecurse \
    $xdc_file

update_compile_order \
    -fileset sources_1

set_property \
    strategy \
    Flow_PerfOptimized_high \
    [get_runs synth_1]

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synthesis_status \
    [get_property STATUS [get_runs synth_1]]

puts ""
puts "Synthesis status: $synthesis_status"

if {![string match "*Complete*" $synthesis_status]} {
    error "Parallel two-tower synthesis failed: $synthesis_status"
}

open_run synth_1

set utilization_report \
    [file join $report_dir poly_mul4096_two_tower_parallel_utilization.rpt]

set hierarchical_report \
    [file join $report_dir poly_mul4096_two_tower_parallel_hierarchical_utilization.rpt]

set timing_report \
    [file join $report_dir poly_mul4096_two_tower_parallel_timing.rpt]

report_utilization \
    -file $utilization_report

report_utilization \
    -hierarchical \
    -hierarchical_depth 12 \
    -file $hierarchical_report

report_timing_summary \
    -delay_type max \
    -max_paths 20 \
    -file $timing_report

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

set bram_tile_equivalent \
    [expr {$ramb36_count + ($ramb18_count / 2.0)}]

set timing_path \
    [lindex [get_timing_paths -delay_type max -max_paths 1] 0]

if {$timing_path eq ""} {
    set wns_ns NA
    set datapath_ns NA
    set logic_levels NA
} else {
    set wns_ns \
        [get_property SLACK $timing_path]

    set datapath_ns \
        [get_property DATAPATH_DELAY $timing_path]

    set logic_levels \
        [get_property LOGIC_LEVELS $timing_path]
}

set summary_file \
    [file join $report_dir poly_mul4096_two_tower_parallel_synthesis_summary.txt]

set fh [open $summary_file w]

puts $fh "project=[file normalize [get_property DIRECTORY [current_project]]]"
puts $fh "top=$top_name"
puts $fh "part=$part_name"
puts $fh "clock_period_ns=$clock_period_ns"
puts $fh "synthesis_status=$synthesis_status"
puts $fh "lanes=2"
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
puts $fh "modulus_lane0=1073692673"
puts $fh "modulus_lane1=1073668097"
puts $fh "coefficient_banks=4"
puts $fh "profile_banks=8"
puts $fh "dual_profile_frame_words=16384"
puts $fh "dual_profile_frame_bytes=131072"
puts $fh "dual_product_input_frame_words=8193"
puts $fh "dual_product_input_frame_bytes=65544"
puts $fh "dual_product_output_frame_words=4096"
puts $fh "dual_product_output_frame_bytes=32768"
puts $fh "parallel_core_cycles=1339394"
puts $fh "parallel_core_latency_us_at_100mhz=13393.94"
puts $fh "modular_multiplications_per_lane=90112"
puts $fh "modular_multiplications_total=180224"
puts $fh "expected_ramb36=48"
puts $fh "utilization_report=[file normalize $utilization_report]"
puts $fh "hierarchical_report=[file normalize $hierarchical_report]"
puts $fh "timing_report=[file normalize $timing_report]"

close $fh

puts ""
puts "============================================================"
puts "PARALLEL TWO-TOWER N=4096 SYNTHESIS COMPLETE"
puts "============================================================"
puts "Lanes:                 2"
puts "LUTs:                  $lut_count"
puts "Registers:             $register_count"
puts "CARRY4:                $carry4_count"
puts "DSP48E1:               $dsp_count"
puts "RAMB18E1:              $ramb18_count"
puts "RAMB36E1:              $ramb36_count"
puts "BRAM tile equivalent:  $bram_tile_equivalent"
puts "WNS:                   $wns_ns ns"
puts "Datapath delay:        $datapath_ns ns"
puts "Logic levels:          $logic_levels"
puts "Parallel core cycles:  1339394"
puts "Parallel latency:      13393.94 us at 100 MHz"
puts "Summary:               $summary_file"
puts "============================================================"
puts ""

close_project
