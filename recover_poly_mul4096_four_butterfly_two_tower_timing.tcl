set root_dir \
    [file dirname [file normalize [info script]]]

set rtl_dir [file join $root_dir rtl]

set report_root \
    [file join \
        $root_dir \
        reports \
        poly_mul4096_four_butterfly_two_tower_timing_recovery \
    ]

set part_name xc7z020clg400-1
set top_name poly_mul4096_four_butterfly_two_tower_synthesis_top
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

proc current_wns {} {
    set path \
        [lindex \
            [get_timing_paths \
                -quiet \
                -delay_type max \
                -max_paths 1 \
            ] \
            0 \
        ]

    if {$path eq ""} {
        return -9999.0
    }

    return [get_property SLACK $path]
}

proc write_strategy_reports {
    strategy_dir
    strategy_name
    checkpoint_name
} {
    file mkdir $strategy_dir

    set utilization_report \
        [file join $strategy_dir utilization.rpt]

    set timing_report \
        [file join $strategy_dir timing_summary.rpt]

    set hierarchical_report \
        [file join $strategy_dir hierarchical_utilization.rpt]

    set checkpoint_file \
        [file join $strategy_dir $checkpoint_name]

    report_utilization \
        -file $utilization_report

    report_utilization \
        -hierarchical \
        -file $hierarchical_report

    report_timing_summary \
        -delay_type max \
        -max_paths 100 \
        -file $timing_report

    write_checkpoint \
        -force \
        $checkpoint_file

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

    set summary_file \
        [file join $strategy_dir implementation_summary.txt]

    set fh [open $summary_file w]

    puts $fh "strategy=$strategy_name"
    puts $fh "implementation_status=Complete"
    puts $fh "wns_ns=$wns_ns"
    puts $fh "datapath_ns=$datapath_ns"
    puts $fh "logic_levels=$logic_levels"
    puts $fh "startpoint=$startpoint"
    puts $fh "endpoint=$endpoint"
    puts $fh "lut=[count_cells {REF_NAME =~ LUT*}]"
    puts $fh "registers=[count_cells {REF_NAME =~ FD*}]"
    puts $fh "carry4=[count_cells {REF_NAME == CARRY4}]"
    puts $fh "dsp=[count_cells {REF_NAME == DSP48E1}]"
    puts $fh "ramb18=[count_cells {REF_NAME == RAMB18E1}]"
    puts $fh "ramb36=[count_cells {REF_NAME == RAMB36E1}]"
    puts $fh "checkpoint=[file normalize $checkpoint_file]"
    puts $fh "timing_report=[file normalize $timing_report]"
    puts $fh "utilization_report=[file normalize $utilization_report]"

    close $fh
}

puts ""
puts "============================================================"
puts "TWO-TOWER TIMING-RECOVERY SWEEP"
puts "============================================================"
puts "Root:  $root_dir"
puts "Part:  $part_name"
puts "Top:   $top_name"
puts "Clock: $clock_period_ns ns"
puts "============================================================"
puts ""

file delete -force $report_root
file mkdir $report_root

set rtl_files [list \
    [file join $rtl_dir modmul_barrett60_pipeline_split_core.sv] \
    [file join $rtl_dir ntt4096_dual_mode_butterfly_pipeline_core.sv] \
    [file join $rtl_dir ntt4096_profile_bram_dual_read.sv] \
    [file join $rtl_dir ntt4096_profile_bram_four_read.sv] \
    [file join $rtl_dir ntt4096_coeff_bank_512x32.sv] \
    [file join $rtl_dir ntt4096_eight_bank_coeff_store_runtime.sv] \
    [file join $rtl_dir ntt4096_four_butterfly_schedule_core.sv] \
    [file join $rtl_dir poly_mul4096_four_lane_arithmetic_core.sv] \
    [file join $rtl_dir poly_mul4096_four_butterfly_pipeline_runtime_profile_core.sv] \
    [file join $rtl_dir poly_mul4096_four_butterfly_two_tower_core.sv] \
    [file join $rtl_dir poly_mul4096_four_butterfly_two_tower_synthesis_top.sv] \
]

foreach path $rtl_files {
    require_file $path
    read_verilog -sv $path
}

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

set synthesis_checkpoint \
    [file join $report_root synthesized.dcp]

write_checkpoint \
    -force \
    $synthesis_checkpoint

# Each entry contains:
#   name
#   opt_design directive
#   place_design directive
#   pre-route phys_opt_design directive
#   route_design directive
#   post-route phys_opt_design directive
#
# These combinations correspond to official Vivado performance and
# congestion-oriented implementation strategies.
set strategies [list \
    [list \
        performance_explore \
        Explore \
        Explore \
        Explore \
        Explore \
        Explore \
    ] \
    [list \
        performance_explore_with_remap \
        ExploreWithRemap \
        Explore \
        Explore \
        NoTimingRelaxation \
        Explore \
    ] \
    [list \
        performance_wl_block_placement \
        Default \
        WLDrivenBlockPlacement \
        Explore \
        Explore \
        Explore \
    ] \
    [list \
        performance_extra_timing_opt \
        Default \
        ExtraTimingOpt \
        Explore \
        NoTimingRelaxation \
        Explore \
    ] \
    [list \
        congestion_spread_logic_high \
        Default \
        AltSpreadLogic_high \
        AggressiveExplore \
        AggressiveExplore \
        AggressiveExplore \
    ] \
]

set best_wns -9999.0
set best_strategy NONE
set best_checkpoint ""
set results_file \
    [file join $report_root strategy_results.tsv]

set results_fh [open $results_file w]
puts $results_fh "strategy\tpre_postroute_wns_ns\tfinal_wns_ns"

foreach strategy $strategies {
    lassign \
        $strategy \
        strategy_name \
        opt_directive \
        place_directive \
        pre_phys_directive \
        route_directive \
        post_phys_directive

    puts ""
    puts "============================================================"
    puts "RUNNING STRATEGY: $strategy_name"
    puts "  opt:        $opt_directive"
    puts "  place:      $place_directive"
    puts "  pre-phys:   $pre_phys_directive"
    puts "  route:      $route_directive"
    puts "  post-phys:  $post_phys_directive"
    puts "============================================================"
    puts ""

    close_design
    open_checkpoint $synthesis_checkpoint

    opt_design \
        -directive $opt_directive

    place_design \
        -directive $place_directive

    phys_opt_design \
        -directive $pre_phys_directive

    route_design \
        -directive $route_directive \
        -tns_cleanup

    set routed_wns \
        [current_wns]

    set strategy_dir \
        [file join \
            $report_root \
            $strategy_name \
        ]

    write_strategy_reports \
        $strategy_dir \
        $strategy_name \
        routed.dcp

    phys_opt_design \
        -directive $post_phys_directive

    set final_wns \
        [current_wns]

    write_strategy_reports \
        $strategy_dir \
        $strategy_name \
        post_route_physopt.dcp

    puts $results_fh \
        "$strategy_name\t$routed_wns\t$final_wns"

    puts ""
    puts "RESULT $strategy_name"
    puts "  routed WNS:          $routed_wns ns"
    puts "  post-route phys WNS: $final_wns ns"
    puts ""

    if {$final_wns > $routed_wns} {
        set candidate_wns \
            $final_wns

        set candidate_checkpoint \
            [file join \
                $strategy_dir \
                post_route_physopt.dcp \
            ]
    } else {
        set candidate_wns \
            $routed_wns

        set candidate_checkpoint \
            [file join \
                $strategy_dir \
                routed.dcp \
            ]
    }

    if {$candidate_wns > $best_wns} {
        set best_wns \
            $candidate_wns

        set best_strategy \
            $strategy_name

        set best_checkpoint \
            $candidate_checkpoint
    }
}

close $results_fh

close_design
open_checkpoint $best_checkpoint

set best_dir \
    [file join \
        $report_root \
        best \
    ]

file mkdir $best_dir

set best_dcp \
    [file join \
        $best_dir \
        routed.dcp \
    ]

write_checkpoint \
    -force \
    $best_dcp

report_timing_summary \
    -delay_type max \
    -max_paths 100 \
    -file \
    [file join \
        $best_dir \
        timing_summary.rpt \
    ]

report_utilization \
    -file \
    [file join \
        $best_dir \
        utilization.rpt \
    ]

set worst_path \
    [lindex \
        [get_timing_paths \
            -quiet \
            -delay_type max \
            -max_paths 1 \
        ] \
        0 \
    ]

set datapath_ns \
    [get_property DATAPATH_DELAY $worst_path]

set logic_levels \
    [get_property LOGIC_LEVELS $worst_path]

set startpoint \
    [get_property STARTPOINT_PIN $worst_path]

set endpoint \
    [get_property ENDPOINT_PIN $worst_path]

set best_summary \
    [file join \
        $best_dir \
        implementation_summary.txt \
    ]

set fh [open $best_summary w]

puts $fh "implementation_status=Complete"
puts $fh "best_strategy=$best_strategy"
puts $fh "wns_ns=$best_wns"
puts $fh "datapath_ns=$datapath_ns"
puts $fh "logic_levels=$logic_levels"
puts $fh "startpoint=$startpoint"
puts $fh "endpoint=$endpoint"
puts $fh "product_cycles=22968"
puts $fh "dsp=[count_cells {REF_NAME == DSP48E1}]"
puts $fh "ramb18=[count_cells {REF_NAME == RAMB18E1}]"
puts $fh "ramb36=[count_cells {REF_NAME == RAMB36E1}]"
puts $fh "checkpoint=[file normalize $best_dcp]"
puts $fh "strategy_results=[file normalize $results_file]"

close $fh

puts ""
puts "============================================================"
puts "TIMING-RECOVERY SWEEP COMPLETE"
puts "============================================================"
puts "Best strategy:  $best_strategy"
puts "Best WNS:       $best_wns ns"
puts "Datapath:       $datapath_ns ns"
puts "Logic levels:   $logic_levels"
puts "Startpoint:     $startpoint"
puts "Endpoint:       $endpoint"
puts "Best DCP:       [file normalize $best_dcp]"
puts "Results table:  [file normalize $results_file]"
puts "============================================================"
puts ""
