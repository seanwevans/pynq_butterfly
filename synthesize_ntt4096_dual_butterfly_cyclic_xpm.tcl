set root_dir [file dirname [file normalize [info script]]]
set rtl_dir [file join $root_dir rtl]

set project_root \
    [file join $root_dir vivado ntt4096_dual_butterfly_cyclic_xpm_synth]

set report_dir \
    [file join $root_dir reports ntt4096_dual_butterfly_cyclic_xpm_synth]

set project_name ntt4096_dual_butterfly_cyclic_xpm_synth
set top_name ntt4096_dual_butterfly_cyclic_core
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
    [file join $rtl_dir modmul_core.sv] \
    [file join $rtl_dir ntt4096_coeff_bank_1024x32.sv] \
    [file join $rtl_dir ntt4096_four_bank_coeff_store.sv] \
    [file join $rtl_dir ntt4096_profile_bram_dual_read.sv] \
    [file join $rtl_dir ntt4096_paired_schedule_core.sv] \
    [file join $rtl_dir ntt4096_dual_mode_butterfly_core.sv] \
    [file join $rtl_dir ntt4096_dual_butterfly_cyclic_core.sv] \
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
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

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
    [file join $project_root ntt4096_dual_butterfly_cyclic_xpm_synth.xdc]

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
    error "Dual-butterfly cyclic XPM synthesis failed: $synthesis_status"
}

open_run synth_1

set utilization_report \
    [file join $report_dir ntt4096_dual_butterfly_cyclic_xpm_utilization.rpt]

set hierarchical_report \
    [file join $report_dir ntt4096_dual_butterfly_cyclic_xpm_hierarchical_utilization.rpt]

set timing_report \
    [file join $report_dir ntt4096_dual_butterfly_cyclic_xpm_timing.rpt]

set bram_cells_report \
    [file join $report_dir ntt4096_dual_butterfly_cyclic_xpm_bram_cells.txt]

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

set timing_paths \
    [get_timing_paths \
        -quiet \
        -delay_type max \
        -from [all_registers] \
        -to [all_registers] \
        -max_paths 1 \
    ]

if {[llength $timing_paths] == 0} {
    set wns_ns NA
    set datapath_ns NA
    set logic_levels NA
} else {
    set timing_path \
        [lindex $timing_paths 0]

    set wns_ns \
        [get_property SLACK $timing_path]

    set datapath_ns \
        [get_property DATAPATH_DELAY $timing_path]

    set logic_levels \
        [get_property LOGIC_LEVELS $timing_path]
}

set fh [open $bram_cells_report w]

foreach cell [get_cells -hierarchical -quiet -filter {
    REF_NAME == RAMB36E1 || REF_NAME == RAMB18E1
}] {
    puts $fh "[get_property REF_NAME $cell] $cell"
}

close $fh

set summary_file \
    [file join $report_dir ntt4096_dual_butterfly_cyclic_xpm_synthesis_summary.txt]

set fh [open $summary_file w]

puts $fh "project=[file normalize [get_property DIRECTORY [current_project]]]"
puts $fh "top=$top_name"
puts $fh "part=$part_name"
puts $fh "clock_period_ns=$clock_period_ns"
puts $fh "synthesis_status=$synthesis_status"
puts $fh "profile_memory_implementation=xpm_memory_tdpram"
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
puts $fh "butterfly_lanes=2"
puts $fh "coefficient_expected_ramb36=4"
puts $fh "twiddle_expected_ramb36=4"
puts $fh "expected_total_ramb36=8"
puts $fh "dual_transform_cycles=270337"
puts $fh "single_transform_reference_cycles=540673"
puts $fh "utilization_report=[file normalize $utilization_report]"
puts $fh "hierarchical_report=[file normalize $hierarchical_report]"
puts $fh "timing_report=[file normalize $timing_report]"
puts $fh "bram_cells_report=[file normalize $bram_cells_report]"

close $fh

puts ""
puts "============================================================"
puts "N=4096 DUAL-BUTTERFLY CYCLIC NTT XPM SYNTHESIS COMPLETE"
puts "============================================================"
puts "Profile memory:         xpm_memory_tdpram"
puts "LUTs:                   $lut_count"
puts "Registers:              $register_count"
puts "CARRY4:                 $carry4_count"
puts "DSP48E1:                $dsp_count"
puts "RAMB18E1:               $ramb18_count"
puts "RAMB36E1:               $ramb36_count"
puts "BRAM tile equivalent:   $bram_tile_equivalent"
puts "WNS:                    $wns_ns ns"
puts "Datapath delay:         $datapath_ns ns"
puts "Logic levels:           $logic_levels"
puts "Expected total RAMB36:  8"
puts "Transform cycles:       270337"
puts "Summary:                $summary_file"
puts "============================================================"
puts ""

close_project
