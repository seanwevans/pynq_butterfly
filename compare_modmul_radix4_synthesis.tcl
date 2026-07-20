set root_dir [file dirname [file normalize [info script]]]
set rtl_dir [file join $root_dir rtl]
set report_dir [file join $root_dir reports modmul_radix4_compare]
set work_root [file join $root_dir vivado modmul_radix4_compare]

set part_name xc7z020clg400-1
set clock_period_ns 10.000

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

proc count_cells {filter_expression} {
    return [llength [
        get_cells \
            -hierarchical \
            -quiet \
            -filter $filter_expression
    ]]
}

proc run_variant {
    variant_name
    top_name
    source_file
    part_name
    clock_period_ns
    work_root
    report_dir
} {
    set project_dir [
        file join \
            $work_root \
            $variant_name
    ]

    set xdc_file [
        file join \
            $project_dir \
            "${variant_name}.xdc"
    ]

    file delete -force $project_dir
    file mkdir $project_dir

    create_project \
        -force \
        $variant_name \
        $project_dir \
        -part $part_name

    set_property \
        target_language \
        Verilog \
        [current_project]

    set_property \
        simulator_language \
        Mixed \
        [current_project]

    add_files \
        -norecurse \
        $source_file

    set_property \
        file_type \
        SystemVerilog \
        [get_files [file normalize $source_file]]

    set_property \
        top \
        $top_name \
        [get_filesets sources_1]

    set xdc_handle [
        open \
            $xdc_file \
            w
    ]

    puts $xdc_handle [
        format \
            {create_clock -name clk -period %.3f [get_ports clk]} \
            $clock_period_ns
    ]

    close $xdc_handle

    add_files \
        -fileset constrs_1 \
        -norecurse \
        $xdc_file

    update_compile_order \
        -fileset sources_1

    reset_run synth_1

    launch_runs \
        synth_1 \
        -jobs 8

    wait_on_run synth_1

    set synthesis_status [
        get_property \
            STATUS \
            [get_runs synth_1]
    ]

    puts "$variant_name synthesis status: $synthesis_status"

    if {![string match "*Complete*" $synthesis_status]} {
        error "$variant_name synthesis failed: $synthesis_status"
    }

    open_run synth_1

    set utilization_report [
        file join \
            $report_dir \
            "${variant_name}_utilization.rpt"
    ]

    set timing_report [
        file join \
            $report_dir \
            "${variant_name}_timing.rpt"
    ]

    report_utilization \
        -file $utilization_report

    report_timing_summary \
        -delay_type max \
        -max_paths 20 \
        -file $timing_report

    set lut_count [
        count_cells {REF_NAME =~ LUT*}
    ]

    set register_count [
        count_cells {REF_NAME =~ FD*}
    ]

    set carry_count [
        count_cells {REF_NAME == CARRY4}
    ]

    set dsp_count [
        count_cells {REF_NAME == DSP48E1}
    ]

    set ramb18_count [
        count_cells {REF_NAME == RAMB18E1}
    ]

    set ramb36_count [
        count_cells {REF_NAME == RAMB36E1}
    ]

    set timing_path [
        lindex [
            get_timing_paths \
                -delay_type max \
                -max_paths 1
        ] \
        0
    ]

    if {$timing_path eq ""} {
        set worst_slack "NA"
        set datapath_delay "NA"
        set logic_levels "NA"
        set startpoint "NA"
        set endpoint "NA"
    } else {
        set worst_slack [
            get_property \
                SLACK \
                $timing_path
        ]

        set datapath_delay [
            get_property \
                DATAPATH_DELAY \
                $timing_path
        ]

        set logic_levels [
            get_property \
                LOGIC_LEVELS \
                $timing_path
        ]

        set startpoint [
            get_property \
                STARTPOINT_PIN \
                $timing_path
        ]

        set endpoint [
            get_property \
                ENDPOINT_PIN \
                $timing_path
        ]
    }

    set result [
        dict create \
            variant $variant_name \
            top $top_name \
            status $synthesis_status \
            lut $lut_count \
            registers $register_count \
            carry4 $carry_count \
            dsp $dsp_count \
            ramb18 $ramb18_count \
            ramb36 $ramb36_count \
            wns_ns $worst_slack \
            datapath_ns $datapath_delay \
            logic_levels $logic_levels \
            startpoint $startpoint \
            endpoint $endpoint \
            utilization_report $utilization_report \
            timing_report $timing_report
    ]

    close_project

    return $result
}

file delete -force $work_root
file delete -force $report_dir

file mkdir $work_root
file mkdir $report_dir

set baseline_source [
    file join \
        $rtl_dir \
        modmul_core.sv
]

set radix4_source [
    file join \
        $rtl_dir \
        modmul_core_radix4.sv
]

require_file $baseline_source
require_file $radix4_source

puts ""
puts "============================================================"
puts "SYNTHESIZING BASELINE MODULAR MULTIPLIER"
puts "============================================================"

set baseline [
    run_variant \
        baseline \
        modmul_core \
        $baseline_source \
        $part_name \
        $clock_period_ns \
        $work_root \
        $report_dir
]

puts ""
puts "============================================================"
puts "SYNTHESIZING RADIX-4 MODULAR MULTIPLIER"
puts "============================================================"

set radix4 [
    run_variant \
        radix4 \
        modmul_core_radix4 \
        $radix4_source \
        $part_name \
        $clock_period_ns \
        $work_root \
        $report_dir
]

set summary_file [
    file join \
        $report_dir \
        modmul_radix4_summary.txt
]

set summary [
    open \
        $summary_file \
        w
]

puts $summary "part=$part_name"
puts $summary "clock_period_ns=$clock_period_ns"
puts $summary ""

foreach result [list $baseline $radix4] {
    set variant [
        dict get \
            $result \
            variant
    ]

    puts $summary "\[$variant\]"

    foreach key [
        list \
            top \
            status \
            lut \
            registers \
            carry4 \
            dsp \
            ramb18 \
            ramb36 \
            wns_ns \
            datapath_ns \
            logic_levels \
            startpoint \
            endpoint \
            utilization_report \
            timing_report
    ] {
        puts $summary [
            format \
                "%s=%s" \
                $key \
                [dict get $result $key]
        ]
    }

    puts $summary ""
}

close $summary

puts ""
puts "============================================================"
puts "MODMUL SYNTHESIS COMPARISON COMPLETE"
puts "============================================================"
puts "Part:         $part_name"
puts "Clock period: $clock_period_ns ns"
puts ""
puts "Baseline:"
puts "  LUTs:        [dict get $baseline lut]"
puts "  Registers:   [dict get $baseline registers]"
puts "  CARRY4:      [dict get $baseline carry4]"
puts "  DSP48E1:     [dict get $baseline dsp]"
puts "  WNS:         [dict get $baseline wns_ns] ns"
puts "  Data path:   [dict get $baseline datapath_ns] ns"
puts "  Logic levels:[dict get $baseline logic_levels]"
puts ""
puts "Radix-4:"
puts "  LUTs:        [dict get $radix4 lut]"
puts "  Registers:   [dict get $radix4 registers]"
puts "  CARRY4:      [dict get $radix4 carry4]"
puts "  DSP48E1:     [dict get $radix4 dsp]"
puts "  WNS:         [dict get $radix4 wns_ns] ns"
puts "  Data path:   [dict get $radix4 datapath_ns] ns"
puts "  Logic levels:[dict get $radix4 logic_levels]"
puts ""
puts "Summary: $summary_file"
puts "============================================================"
puts ""
