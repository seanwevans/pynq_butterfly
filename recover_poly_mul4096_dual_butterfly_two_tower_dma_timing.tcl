set root_dir F:/repos/pynq_butterfly
set project_file F:/v/db2/db2.xpr
set run_name impl_1

set deploy_dir \
    [file join $root_dir deploy poly_mul4096_dual_butterfly_two_tower_dma]

set report_dir \
    [file join $root_dir reports poly_mul4096_dual_butterfly_two_tower_dma_timing_recovery]

set bit_name \
    poly_mul4096_dual_butterfly_two_tower_dma

proc require_path {path} {
    if {![file exists $path]} {
        error "Required path does not exist: $path"
    }
}

proc count_cells {filter_expression} {
    return [llength \
        [get_cells -hierarchical -quiet -filter $filter_expression]
    ]
}

require_path $project_file

file delete -force $report_dir
file mkdir $report_dir

open_project $project_file

set implementation_run \
    [get_runs $run_name]

if {[llength $implementation_run] != 1} {
    error "Could not resolve implementation run: $run_name"
}

set recovery_strategy \
    Performance_ExplorePostRoutePhysOpt

puts ""
puts "============================================================"
puts "RERUNNING IMPLEMENTATION FOR 100 MHZ TIMING RECOVERY"
puts "============================================================"
puts "Project:   $project_file"
puts "Run:       $run_name"
puts "Strategy:  $recovery_strategy"
puts "============================================================"
puts ""

reset_run $implementation_run

set_property \
    strategy \
    $recovery_strategy \
    $implementation_run

launch_runs \
    $implementation_run \
    -to_step write_bitstream \
    -jobs 8

wait_on_run $implementation_run

set implementation_status \
    [get_property STATUS $implementation_run]

puts ""
puts "Implementation status: $implementation_status"

if {![string match "*Complete*" $implementation_status]} {
    error "Timing-recovery implementation failed: $implementation_status"
}

open_run $implementation_run

set timing_report \
    [file join $report_dir timing_summary.rpt]

set utilization_report \
    [file join $report_dir utilization.rpt]

report_timing_summary \
    -delay_type max \
    -max_paths 50 \
    -file $timing_report

report_utilization \
    -file $utilization_report

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
    set wns_ns NA
    set datapath_ns NA
    set logic_levels NA
    set startpoint NA
    set endpoint NA
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

set dsp_count \
    [count_cells {REF_NAME == DSP48E1}]

set ramb18_count \
    [count_cells {REF_NAME == RAMB18E1}]

set ramb36_count \
    [count_cells {REF_NAME == RAMB36E1}]

set bram_tile_equivalent \
    [expr {$ramb36_count + ($ramb18_count / 2.0)}]

set summary_file \
    [file join $report_dir timing_recovery_summary.txt]

set summary_handle \
    [open $summary_file w]

puts $summary_handle "project=$project_file"
puts $summary_handle "run=$run_name"
puts $summary_handle "strategy=$recovery_strategy"
puts $summary_handle "implementation_status=$implementation_status"
puts $summary_handle "wns_ns=$wns_ns"
puts $summary_handle "datapath_ns=$datapath_ns"
puts $summary_handle "logic_levels=$logic_levels"
puts $summary_handle "startpoint=$startpoint"
puts $summary_handle "endpoint=$endpoint"
puts $summary_handle "lut=$lut_count"
puts $summary_handle "registers=$register_count"
puts $summary_handle "dsp=$dsp_count"
puts $summary_handle "ramb18=$ramb18_count"
puts $summary_handle "ramb36=$ramb36_count"
puts $summary_handle "bram_tile_equivalent=$bram_tile_equivalent"
puts $summary_handle "timing_report=[file normalize $timing_report]"
puts $summary_handle "utilization_report=[file normalize $utilization_report]"

close $summary_handle

puts ""
puts "============================================================"
puts "TIMING-RECOVERY RESULT"
puts "============================================================"
puts "Strategy:               $recovery_strategy"
puts "WNS:                    $wns_ns ns"
puts "Datapath delay:         $datapath_ns ns"
puts "Logic levels:           $logic_levels"
puts "Startpoint:             $startpoint"
puts "Endpoint:               $endpoint"
puts "LUTs:                   $lut_count"
puts "Registers:              $register_count"
puts "DSP48E1:                $dsp_count"
puts "RAMB18E1:               $ramb18_count"
puts "RAMB36E1:               $ramb36_count"
puts "BRAM tile equivalent:   $bram_tile_equivalent"
puts "Summary:                $summary_file"
puts "============================================================"
puts ""

if {
    $wns_ns ne "NA"
    && [expr {double($wns_ns)}] >= 0.0
} {
    set project_directory \
        [get_property DIRECTORY [current_project]]

    set project_name \
        [get_property NAME [current_project]]

    set design_name d

    set bit_source \
        [file join \
            $project_directory \
            ${project_name}.runs \
            $run_name \
            ${design_name}_wrapper.bit \
        ]

    set hwh_source \
        [file join \
            $project_directory \
            ${project_name}.gen \
            sources_1 \
            bd \
            $design_name \
            hw_handoff \
            ${design_name}.hwh \
        ]

    require_path $bit_source
    require_path $hwh_source

    file mkdir $deploy_dir

    set bit_destination \
        [file join $deploy_dir ${bit_name}.bit]

    set hwh_destination \
        [file join $deploy_dir ${bit_name}.hwh]

    file copy -force \
        $bit_source \
        $bit_destination

    file copy -force \
        $hwh_source \
        $hwh_destination

    set xsa_destination \
        [file join $deploy_dir ${bit_name}.xsa]

    write_hw_platform \
        -fixed \
        -include_bit \
        -force \
        $xsa_destination

    set pass_file \
        [file join $deploy_dir timing_clean.txt]

    set pass_handle \
        [open $pass_file w]

    puts $pass_handle "timing_clean=true"
    puts $pass_handle "strategy=$recovery_strategy"
    puts $pass_handle "wns_ns=$wns_ns"
    puts $pass_handle "bit=[file normalize $bit_destination]"
    puts $pass_handle "hwh=[file normalize $hwh_destination]"
    puts $pass_handle "xsa=[file normalize $xsa_destination]"
    puts $pass_handle "timing_report=[file normalize $timing_report]"

    close $pass_handle

    puts "PASS: 100 MHz timing closed."
    puts "Updated BIT: [file normalize $bit_destination]"
    puts "Updated HWH: [file normalize $hwh_destination]"
    puts "Updated XSA: [file normalize $xsa_destination]"
} else {
    puts "FAIL: 100 MHz timing still has negative slack."
    puts "The deployed bitstream was not replaced."
    puts "Use the reported startpoint and endpoint for the RTL timing fix."
}

close_project
