set source_root F:/repos/pynq_butterfly
set ip_repo F:/v/ip

set project_root F:/v/db2ti
set project_name db2ti
set design_name d

set ip_vlnv user.org:user:db2ti:1.1
set board_part tul.com.tw:pynq-z2:part0:1.0
set part_name xc7z020clg400-1

set deploy_dir \
    [file join \
        $source_root \
        deploy \
        poly_mul4096_dual_butterfly_two_tower_dma \
    ]

set report_dir \
    [file join \
        $source_root \
        reports \
        poly_mul4096_dual_butterfly_two_tower_dma_timing_isolated \
    ]

proc require_path {path} {
    if {![file exists $path]} {
        error "Required path does not exist: $path"
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

require_path $ip_repo

file delete -force $project_root
file delete -force $deploy_dir
file delete -force $report_dir

file mkdir $project_root
file mkdir $deploy_dir
file mkdir $report_dir

create_project \
    -force \
    $project_name \
    $project_root \
    -part $part_name

set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property ip_repo_paths [list $ip_repo] [current_project]

update_ip_catalog

if {[llength [get_ipdefs -all $ip_vlnv]] == 0} {
    error "Packaged IP is not present in the catalog: $ip_vlnv"
}

create_bd_design $design_name

set ps \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:processing_system7:5.5 \
        ps \
    ]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {
        make_external "FIXED_IO, DDR"
        apply_board_preset "1"
        Master "Disable"
        Slave "Disable"
    } \
    $ps

set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
] $ps

set rst \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
        rst \
    ]

set_property \
    -dict [list \
        CONFIG.C_EXT_RESET_HIGH {0} \
    ] \
    $rst

set dma \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:axi_dma:7.1 \
        dma \
    ]

set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
    CONFIG.c_sg_length_width {26} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_include_s2mm_dre {0} \
] $dma

set ctl \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        ctl \
    ]

set_property \
    -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {1} \
    ] \
    $ctl

set mem \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        mem \
    ]

set_property \
    -dict [list \
        CONFIG.NUM_SI {2} \
        CONFIG.NUM_MI {1} \
    ] \
    $mem

set acc \
    [create_bd_cell \
        -type ip \
        -vlnv $ip_vlnv \
        acc \
    ]

connect_bd_intf_net \
    [get_bd_intf_pins ps/M_AXI_GP0] \
    [get_bd_intf_pins ctl/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins ctl/M00_AXI] \
    [get_bd_intf_pins dma/S_AXI_LITE]

connect_bd_intf_net \
    [get_bd_intf_pins dma/M_AXI_MM2S] \
    [get_bd_intf_pins mem/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins dma/M_AXI_S2MM] \
    [get_bd_intf_pins mem/S01_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins mem/M00_AXI] \
    [get_bd_intf_pins ps/S_AXI_HP0]

connect_bd_intf_net \
    [get_bd_intf_pins dma/M_AXIS_MM2S] \
    [get_bd_intf_pins acc/s_axis]

connect_bd_intf_net \
    [get_bd_intf_pins acc/m_axis] \
    [get_bd_intf_pins dma/S_AXIS_S2MM]

set clk [get_bd_pins ps/FCLK_CLK0]

connect_bd_net \
    $clk \
    [get_bd_pins ps/M_AXI_GP0_ACLK] \
    [get_bd_pins ps/S_AXI_HP0_ACLK] \
    [get_bd_pins rst/slowest_sync_clk] \
    [get_bd_pins dma/s_axi_lite_aclk] \
    [get_bd_pins dma/m_axi_mm2s_aclk] \
    [get_bd_pins dma/m_axi_s2mm_aclk] \
    [get_bd_pins ctl/aclk] \
    [get_bd_pins mem/aclk] \
    [get_bd_pins acc/clk]

connect_bd_net \
    [get_bd_pins ps/FCLK_RESET0_N] \
    [get_bd_pins rst/ext_reset_in]

connect_bd_net \
    [get_bd_pins rst/interconnect_aresetn] \
    [get_bd_pins ctl/aresetn] \
    [get_bd_pins mem/aresetn]

connect_bd_net \
    [get_bd_pins rst/peripheral_aresetn] \
    [get_bd_pins dma/axi_resetn] \
    [get_bd_pins acc/reset_n]

assign_bd_address

validate_bd_design
save_bd_design

set wrapper_files \
    [make_wrapper \
        -files [get_files ${design_name}.bd] \
        -top \
    ]

add_files \
    -norecurse \
    $wrapper_files

set_property \
    top \
    ${design_name}_wrapper \
    [get_filesets sources_1]

update_compile_order \
    -fileset sources_1

set_property \
    strategy \
    Flow_PerfOptimized_high \
    [get_runs synth_1]

set_property \
    strategy \
    Performance_ExplorePostRoutePhysOpt \
    [get_runs impl_1]

launch_runs \
    impl_1 \
    -to_step write_bitstream \
    -jobs 8

wait_on_run impl_1

set implementation_status \
    [get_property STATUS [get_runs impl_1]]

puts ""
puts "Implementation status: $implementation_status"

if {![string match "*Complete*" $implementation_status]} {
    error "Timing-isolated DMA implementation failed: $implementation_status"
}

open_run impl_1

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
    set wns_ns [get_property SLACK $worst_path]
    set datapath_ns [get_property DATAPATH_DELAY $worst_path]
    set logic_levels [get_property LOGIC_LEVELS $worst_path]
    set startpoint [get_property STARTPOINT_PIN $worst_path]
    set endpoint [get_property ENDPOINT_PIN $worst_path]
}

set lut_count [count_cells {REF_NAME =~ LUT*}]
set register_count [count_cells {REF_NAME =~ FD*}]
set dsp_count [count_cells {REF_NAME == DSP48E1}]
set ramb18_count [count_cells {REF_NAME == RAMB18E1}]
set ramb36_count [count_cells {REF_NAME == RAMB36E1}]

set bram_tile_equivalent \
    [expr {$ramb36_count + ($ramb18_count / 2.0)}]

set project_directory \
    [get_property DIRECTORY [current_project]]

set bit_source \
    [file join \
        $project_directory \
        ${project_name}.runs \
        impl_1 \
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

set artifact_name \
    poly_mul4096_dual_butterfly_two_tower_dma

set bit_destination \
    [file join $deploy_dir ${artifact_name}.bit]

set hwh_destination \
    [file join $deploy_dir ${artifact_name}.hwh]

set xsa_destination \
    [file join $deploy_dir ${artifact_name}.xsa]

file copy -force $bit_source $bit_destination
file copy -force $hwh_source $hwh_destination

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    $xsa_destination

set manifest_file \
    [file join $deploy_dir manifest.txt]

set fh [open $manifest_file w]

puts $fh "overlay=$artifact_name"
puts $fh "vivado_project_root=$project_root"
puts $fh "vivado_project_name=$project_name"
puts $fh "vivado_design_name=$design_name"
puts $fh "ip_vlnv=$ip_vlnv"
puts $fh "board_part=$board_part"
puts $fh "part=$part_name"
puts $fh "clock_mhz=100"
puts $fh "tower_lanes=2"
puts $fh "stream_width_bits=64"
puts $fh "profile_command=0x50524f46"
puts $fh "dual_profile_frame_words=16384"
puts $fh "dual_profile_frame_bytes=131072"
puts $fh "product_command=0x4d554c31"
puts $fh "dual_product_input_frame_words=8193"
puts $fh "dual_product_input_frame_bytes=65544"
puts $fh "dual_product_output_frame_words=4096"
puts $fh "dual_product_output_frame_bytes=32768"
puts $fh "butterfly_inputs_registered=true"
puts $fh "total_modmul_lanes=24"
puts $fh "expected_core_ramb36=48"
puts $fh "parallel_core_cycles=631810"
puts $fh "parallel_core_latency_us=6318.10"
puts $fh "previous_parallel_core_cycles=1339394"
puts $fh "core_cycle_speedup=[expr {1339394.0 / 631810.0}]"
puts $fh "implementation_strategy=Performance_ExplorePostRoutePhysOpt"
puts $fh "implementation_status=$implementation_status"
puts $fh "wns_ns=$wns_ns"
puts $fh "datapath_ns=$datapath_ns"
puts $fh "logic_levels=$logic_levels"
puts $fh "startpoint=$startpoint"
puts $fh "endpoint=$endpoint"
puts $fh "lut=$lut_count"
puts $fh "registers=$register_count"
puts $fh "dsp=$dsp_count"
puts $fh "ramb18=$ramb18_count"
puts $fh "ramb36=$ramb36_count"
puts $fh "bram_tile_equivalent=$bram_tile_equivalent"
puts $fh "bit=[file normalize $bit_destination]"
puts $fh "hwh=[file normalize $hwh_destination]"
puts $fh "xsa=[file normalize $xsa_destination]"
puts $fh "timing_report=[file normalize $timing_report]"
puts $fh "utilization_report=[file normalize $utilization_report]"

close $fh

puts ""
puts "============================================================"
puts "TIMING-ISOLATED PYNQ-Z2 DMA OVERLAY COMPLETE"
puts "============================================================"
puts "Implementation:          $implementation_status"
puts "WNS:                     $wns_ns ns"
puts "Datapath delay:          $datapath_ns ns"
puts "Logic levels:            $logic_levels"
puts "Startpoint:              $startpoint"
puts "Endpoint:                $endpoint"
puts "LUTs:                    $lut_count"
puts "Registers:               $register_count"
puts "DSP48E1:                 $dsp_count"
puts "RAMB18E1:                $ramb18_count"
puts "RAMB36E1:                $ramb36_count"
puts "BRAM tile equivalent:    $bram_tile_equivalent"
puts "Parallel core cycles:    631810"
puts "Core latency:            6318.10 us"
puts "Manifest:                [file normalize $manifest_file]"
puts "============================================================"
puts ""

close_project
