set root_dir [file dirname [file normalize [info script]]]

set ip_repo \
    [file join $root_dir ip]

set ip_vlnv \
    user.org:user:poly_mul4096_dual_butterfly_two_tower_axis:1.0

set project_root \
    F:/repos/pynq_poly_mul4096_dual_butterfly_two_tower_dma

set project_name \
    pynq_poly_mul4096_dual_butterfly_two_tower_dma

set design_name \
    design_1

set board_part \
    tul.com.tw:pynq-z2:part0:1.0

set part_name \
    xc7z020clg400-1

set deploy_dir \
    [file join $root_dir deploy poly_mul4096_dual_butterfly_two_tower_dma]

set report_dir \
    [file join $root_dir reports poly_mul4096_dual_butterfly_two_tower_dma]

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

set_property \
    board_part \
    $board_part \
    [current_project]

set_property \
    target_language \
    Verilog \
    [current_project]

set_property \
    XPM_LIBRARIES \
    {XPM_MEMORY} \
    [current_project]

set_property \
    ip_repo_paths \
    [list $ip_repo] \
    [current_project]

update_ip_catalog

if {
    [llength [get_ipdefs -all $ip_vlnv]] == 0
} {
    error "Packaged IP is not present in the catalog: $ip_vlnv"
}

create_bd_design \
    $design_name

set ps7 \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:processing_system7:5.5 \
        processing_system7_0 \
    ]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {
        make_external "FIXED_IO, DDR"
        apply_board_preset "1"
        Master "Disable"
        Slave "Disable"
    } \
    $ps7

set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
] $ps7

set reset_block \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
        proc_sys_reset_0 \
    ]

set_property \
    -dict [list \
        CONFIG.C_EXT_RESET_HIGH {0} \
    ] \
    $reset_block

set dma \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:axi_dma:7.1 \
        axi_dma_0 \
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

set control_connect \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        axi_smc_control \
    ]

set_property \
    -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {1} \
    ] \
    $control_connect

set memory_connect \
    [create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        axi_smc_memory \
    ]

set_property \
    -dict [list \
        CONFIG.NUM_SI {2} \
        CONFIG.NUM_MI {1} \
    ] \
    $memory_connect

set accelerator \
    [create_bd_cell \
        -type ip \
        -vlnv $ip_vlnv \
        poly_mul4096_dual_butterfly_two_tower_axis_0 \
    ]

connect_bd_intf_net \
    [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_smc_control/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_smc_control/M00_AXI] \
    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] \
    [get_bd_intf_pins axi_smc_memory/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
    [get_bd_intf_pins axi_smc_memory/S01_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_smc_memory/M00_AXI] \
    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins poly_mul4096_dual_butterfly_two_tower_axis_0/s_axis]

connect_bd_intf_net \
    [get_bd_intf_pins poly_mul4096_dual_butterfly_two_tower_axis_0/m_axis] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

set clock_source \
    [get_bd_pins processing_system7_0/FCLK_CLK0]

connect_bd_net \
    $clock_source \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
    [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
    [get_bd_pins axi_smc_control/aclk] \
    [get_bd_pins axi_smc_memory/aclk] \
    [get_bd_pins poly_mul4096_dual_butterfly_two_tower_axis_0/clk]

connect_bd_net \
    [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

connect_bd_net \
    [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
    [get_bd_pins axi_smc_control/aresetn] \
    [get_bd_pins axi_smc_memory/aresetn]

connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn] \
    [get_bd_pins poly_mul4096_dual_butterfly_two_tower_axis_0/reset_n]

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
    Performance_Explore \
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

if {
    ![string match "*Complete*" $implementation_status]
} {
    error "Dual-butterfly two-tower DMA implementation failed: $implementation_status"
}

open_run impl_1

set timing_report \
    [file join $report_dir poly_mul4096_dual_butterfly_two_tower_dma_timing.rpt]

set utilization_report \
    [file join $report_dir poly_mul4096_dual_butterfly_two_tower_dma_utilization.rpt]

report_timing_summary \
    -delay_type max \
    -max_paths 30 \
    -file $timing_report

report_utilization \
    -file $utilization_report

set worst_path \
    [lindex \
        [get_timing_paths -delay_type max -max_paths 1] \
        0 \
    ]

if {$worst_path eq ""} {
    set wns_ns NA
} else {
    set wns_ns \
        [get_property SLACK $worst_path]
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

set bit_source \
    [file join \
        $project_root \
        ${project_name}.runs \
        impl_1 \
        ${design_name}_wrapper.bit \
    ]

set hwh_source \
    [file join \
        $project_root \
        ${project_name}.gen \
        sources_1 \
        bd \
        $design_name \
        hw_handoff \
        ${design_name}.hwh \
    ]

require_path $bit_source
require_path $hwh_source

set bit_destination \
    [file join \
        $deploy_dir \
        poly_mul4096_dual_butterfly_two_tower_dma.bit \
    ]

set hwh_destination \
    [file join \
        $deploy_dir \
        poly_mul4096_dual_butterfly_two_tower_dma.hwh \
    ]

file copy -force \
    $bit_source \
    $bit_destination

file copy -force \
    $hwh_source \
    $hwh_destination

set xsa_destination \
    [file join \
        $deploy_dir \
        poly_mul4096_dual_butterfly_two_tower_dma.xsa \
    ]

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    $xsa_destination

set manifest_file \
    [file join $deploy_dir manifest.txt]

set manifest_handle \
    [open $manifest_file w]

puts $manifest_handle "overlay=poly_mul4096_dual_butterfly_two_tower_dma"
puts $manifest_handle "board_part=$board_part"
puts $manifest_handle "part=$part_name"
puts $manifest_handle "ip_vlnv=$ip_vlnv"
puts $manifest_handle "clock_mhz=100"
puts $manifest_handle "tower_lanes=2"
puts $manifest_handle "stream_width_bits=64"
puts $manifest_handle "modulus_lane0=1073692673"
puts $manifest_handle "modulus_lane1=1073668097"
puts $manifest_handle "profile_command=0x50524f46"
puts $manifest_handle "dual_profile_frame_words=16384"
puts $manifest_handle "dual_profile_frame_bytes=131072"
puts $manifest_handle "product_command=0x4d554c31"
puts $manifest_handle "dual_product_input_frame_words=8193"
puts $manifest_handle "dual_product_input_frame_bytes=65544"
puts $manifest_handle "dual_product_output_frame_words=4096"
puts $manifest_handle "dual_product_output_frame_bytes=32768"
puts $manifest_handle "butterfly_lanes_per_tower=2"
puts $manifest_handle "total_modmul_lanes=24"
puts $manifest_handle "coefficient_ramb36_core=16"
puts $manifest_handle "profile_ramb36_core=32"
puts $manifest_handle "parallel_core_cycles=607234"
puts $manifest_handle "parallel_core_latency_us=6072.34"
puts $manifest_handle "previous_parallel_core_cycles=1339394"
puts $manifest_handle "core_cycle_speedup=2.2057295869467124"
puts $manifest_handle "modular_multiplications_per_lane=90112"
puts $manifest_handle "modular_multiplications_total=180224"
puts $manifest_handle "expected_core_ramb36=48"
puts $manifest_handle "implementation_status=$implementation_status"
puts $manifest_handle "wns_ns=$wns_ns"
puts $manifest_handle "lut=$lut_count"
puts $manifest_handle "registers=$register_count"
puts $manifest_handle "dsp=$dsp_count"
puts $manifest_handle "ramb18=$ramb18_count"
puts $manifest_handle "ramb36=$ramb36_count"
puts $manifest_handle "bram_tile_equivalent=$bram_tile_equivalent"
puts $manifest_handle "bit=[file normalize $bit_destination]"
puts $manifest_handle "hwh=[file normalize $hwh_destination]"
puts $manifest_handle "xsa=[file normalize $xsa_destination]"
puts $manifest_handle "timing_report=[file normalize $timing_report]"
puts $manifest_handle "utilization_report=[file normalize $utilization_report]"

close $manifest_handle

puts ""
puts "============================================================"
puts "PYNQ-Z2 DUAL-BUTTERFLY TWO-TOWER DMA OVERLAY COMPLETE"
puts "============================================================"
puts "Implementation:        $implementation_status"
puts "WNS:                   $wns_ns ns"
puts "LUTs:                  $lut_count"
puts "Registers:             $register_count"
puts "DSP48E1:               $dsp_count"
puts "RAMB18E1:              $ramb18_count"
puts "RAMB36E1:              $ramb36_count"
puts "BRAM tile equivalent:  $bram_tile_equivalent"
puts "Parallel core cycles:  607234"
puts "Core latency:          6072.34 us"
puts "BIT:                   [file normalize $bit_destination]"
puts "HWH:                   [file normalize $hwh_destination]"
puts "XSA:                   [file normalize $xsa_destination]"
puts "Manifest:              [file normalize $manifest_file]"
puts "============================================================"
puts ""

close_project
