# Build a complete PYNQ-Z2 AXI-DMA overlay for exact fused two-tower
# EvalMul3 plus host-decomposed OpenFHE BV relinearization.
#
# Usage:
#   vivado -mode batch -source build_evalmul3_bv_relinearized_dma150_overlay.tcl \
#     -tclargs REPO_ROOT BUILD_ROOT DEPLOY_DIR

if {[llength $argv] != 3} {
    puts stderr \
        "usage: build_evalmul3_bv_relinearized_dma150_overlay.tcl REPO_ROOT BUILD_ROOT DEPLOY_DIR"
    exit 2
}

set repo_root [file normalize [lindex $argv 0]]
set build_root [file normalize [lindex $argv 1]]
set deploy_dir [file normalize [lindex $argv 2]]

set project_name "evalmul3_bv_relinearized_dma150"
set bd_name "d"
set part "xc7z020clg400-1"
set board_part "tul.com.tw:pynq-z2:part0:1.0"
set core_clock_mhz 100.000
set memory_clock_mhz 150.000

file mkdir $build_root
file mkdir $deploy_dir

set project_dir [file join $build_root $project_name]
set summary_path [file join $build_root "build_summary.txt"]
set summary_file [open $summary_path "w"]

proc summary_puts {channel text} {
    puts $text
    puts $channel $text
    flush $channel
}

summary_puts $summary_file "EVALMUL3_BV_RELINEARIZED_DMA150_BUILD_BEGIN"
summary_puts $summary_file "repo_root=$repo_root"
summary_puts $summary_file "build_root=$build_root"
summary_puts $summary_file "deploy_dir=$deploy_dir"
summary_puts $summary_file "part=$part"
summary_puts $summary_file "board_part=$board_part"
summary_puts $summary_file "core_clock_mhz=$core_clock_mhz"
summary_puts $summary_file "memory_clock_mhz=$memory_clock_mhz"

set_param general.maxThreads 1

create_project \
    $project_name \
    $project_dir \
    -part $part \
    -force

if {[catch {
    set_property \
        board_part \
        $board_part \
        [current_project]
} board_error]} {
    summary_puts $summary_file \
        "ERROR: PYNQ-Z2 board part is unavailable: $board_error"

    summary_puts $summary_file \
        "Available matching board parts: [get_board_parts -quiet *pynq*]"

    close $summary_file
    exit 3
}

set rtl_files [list \
    [file join \
        $repo_root \
        "rtl" \
        "modmul_barrett60_pipeline_split_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "evalmul3_two_tower_axis_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "bv_keyswitch_mac_two_tower_axis_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "evalmul3_bv_relinearize_two_tower_axis_core.sv"] \
    [file join \
        $repo_root \
        "rtl" \
        "evalmul3_bv_relinearized_axis_dma_wrapper.v"] \
]

foreach rtl_file $rtl_files {
    if {![file isfile $rtl_file]} {
        summary_puts $summary_file \
            "ERROR: missing RTL file: $rtl_file"

        close $summary_file
        exit 4
    }

    add_files \
        -norecurse \
        $rtl_file
}

set wrapper_file [
    file join \
        $repo_root \
        "rtl" \
        "evalmul3_bv_relinearized_axis_dma_wrapper.v"
]

set_property \
    file_type \
    Verilog \
    [get_files $wrapper_file]

update_compile_order \
    -fileset sources_1

create_bd_design $bd_name

set ps7 [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:processing_system7:5.5 \
        ps7
]

apply_bd_automation \
    -rule xilinx.com:bd_rule:processing_system7 \
    -config {
        apply_board_preset "1"
        make_external "FIXED_IO, DDR"
        Master "Disable"
        Slave "Disable"
    } \
    $ps7

set_property \
    -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0 {1} \
        CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_USE_S_AXI_HP1 {1} \
        CONFIG.PCW_EN_CLK1_PORT {1} \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $core_clock_mhz \
        CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ $memory_clock_mhz \
    ] \
    $ps7

set dma [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:axi_dma:7.1 \
        dma
]

set_property \
    -dict [list \
        CONFIG.c_include_sg {0} \
        CONFIG.c_include_mm2s {1} \
        CONFIG.c_include_s2mm {1} \
        CONFIG.c_sg_length_width {26} \
        CONFIG.c_m_axi_mm2s_data_width {64} \
        CONFIG.c_m_axis_mm2s_tdata_width {64} \
        CONFIG.c_include_mm2s_dre {0} \
        CONFIG.c_mm2s_burst_size {16} \
        CONFIG.c_m_axi_s2mm_data_width {64} \
        CONFIG.c_s_axis_s2mm_tdata_width {64} \
        CONFIG.c_include_s2mm_dre {0} \
        CONFIG.c_s2mm_burst_size {16} \
    ] \
    $dma

set accel [
    create_bd_cell \
        -type module \
        -reference evalmul3_bv_relinearized_axis_dma_wrapper \
        relin
]

set reset_100m [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
        reset_100m
]

set reset_150m [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
        reset_150m
]

set mm2s_cdc [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:axis_clock_converter:1.1 \
        mm2s_cdc
]

set_property \
    -dict [list \
        CONFIG.TDATA_NUM_BYTES {8} \
        CONFIG.HAS_TKEEP {1} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.IS_ACLK_ASYNC {1} \
        CONFIG.FIFO_DEPTH {1024} \
        CONFIG.SYNCHRONIZATION_STAGES {3} \
    ] \
    $mm2s_cdc

set s2mm_cdc [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:axis_clock_converter:1.1 \
        s2mm_cdc
]

set_property \
    -dict [list \
        CONFIG.TDATA_NUM_BYTES {8} \
        CONFIG.HAS_TKEEP {1} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.IS_ACLK_ASYNC {1} \
        CONFIG.FIFO_DEPTH {1024} \
        CONFIG.SYNCHRONIZATION_STAGES {3} \
    ] \
    $s2mm_cdc

set control_interconnect [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        control_sc
]

set_property \
    -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {1} \
    ] \
    $control_interconnect

set mm2s_interconnect [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        mm2s_sc
]

set_property \
    -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {1} \
    ] \
    $mm2s_interconnect

set s2mm_interconnect [
    create_bd_cell \
        -type ip \
        -vlnv xilinx.com:ip:smartconnect:1.0 \
        s2mm_sc
]

set_property \
    -dict [list \
        CONFIG.NUM_SI {1} \
        CONFIG.NUM_MI {1} \
    ] \
    $s2mm_interconnect

connect_bd_intf_net \
    [get_bd_intf_pins ps7/M_AXI_GP0] \
    [get_bd_intf_pins control_sc/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins control_sc/M00_AXI] \
    [get_bd_intf_pins dma/S_AXI_LITE]

connect_bd_intf_net \
    [get_bd_intf_pins dma/M_AXI_MM2S] \
    [get_bd_intf_pins mm2s_sc/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins mm2s_sc/M00_AXI] \
    [get_bd_intf_pins ps7/S_AXI_HP0]

connect_bd_intf_net \
    [get_bd_intf_pins dma/M_AXI_S2MM] \
    [get_bd_intf_pins s2mm_sc/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins s2mm_sc/M00_AXI] \
    [get_bd_intf_pins ps7/S_AXI_HP1]

connect_bd_intf_net \
    [get_bd_intf_pins dma/M_AXIS_MM2S] \
    [get_bd_intf_pins mm2s_cdc/S_AXIS]

connect_bd_intf_net \
    [get_bd_intf_pins mm2s_cdc/M_AXIS] \
    [get_bd_intf_pins relin/S_AXIS]

connect_bd_intf_net \
    [get_bd_intf_pins relin/M_AXIS] \
    [get_bd_intf_pins s2mm_cdc/S_AXIS]

connect_bd_intf_net \
    [get_bd_intf_pins s2mm_cdc/M_AXIS] \
    [get_bd_intf_pins dma/S_AXIS_S2MM]

set core_clock [
    get_bd_pins ps7/FCLK_CLK0
]

set memory_clock [
    get_bd_pins ps7/FCLK_CLK1
]

connect_bd_net \
    $core_clock \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins dma/s_axi_lite_aclk] \
    [get_bd_pins control_sc/aclk] \
    [get_bd_pins reset_100m/slowest_sync_clk] \
    [get_bd_pins mm2s_cdc/m_axis_aclk] \
    [get_bd_pins s2mm_cdc/s_axis_aclk] \
    [get_bd_pins relin/aclk]

connect_bd_net \
    $memory_clock \
    [get_bd_pins ps7/S_AXI_HP0_ACLK] \
    [get_bd_pins ps7/S_AXI_HP1_ACLK] \
    [get_bd_pins dma/m_axi_mm2s_aclk] \
    [get_bd_pins dma/m_axi_s2mm_aclk] \
    [get_bd_pins mm2s_sc/aclk] \
    [get_bd_pins s2mm_sc/aclk] \
    [get_bd_pins reset_150m/slowest_sync_clk] \
    [get_bd_pins mm2s_cdc/s_axis_aclk] \
    [get_bd_pins s2mm_cdc/m_axis_aclk]

connect_bd_net \
    [get_bd_pins ps7/FCLK_RESET0_N] \
    [get_bd_pins reset_100m/ext_reset_in] \
    [get_bd_pins reset_150m/ext_reset_in]

connect_bd_net \
    [get_bd_pins reset_100m/interconnect_aresetn] \
    [get_bd_pins control_sc/aresetn]

connect_bd_net \
    [get_bd_pins reset_150m/interconnect_aresetn] \
    [get_bd_pins mm2s_sc/aresetn] \
    [get_bd_pins s2mm_sc/aresetn]

connect_bd_net \
    [get_bd_pins reset_100m/peripheral_aresetn] \
    [get_bd_pins dma/axi_resetn] \
    [get_bd_pins mm2s_cdc/m_axis_aresetn] \
    [get_bd_pins s2mm_cdc/s_axis_aresetn] \
    [get_bd_pins relin/aresetn]

connect_bd_net \
    [get_bd_pins reset_150m/peripheral_aresetn] \
    [get_bd_pins mm2s_cdc/s_axis_aresetn] \
    [get_bd_pins s2mm_cdc/m_axis_aresetn]

# Auto assignment already places the DMA control register segment at:
#
#     ps7/Data -> dma/S_AXI_LITE/Reg
#     0x4040_0000, range 64K
#
# OFFSET and RANGE on the slave segment are read-only after assignment.
# Do not attempt to rewrite them with set_property.
assign_bd_address

validate_bd_design
save_bd_design

generate_target \
    all \
    [get_files ${bd_name}.bd]

make_wrapper \
    -files [get_files ${bd_name}.bd] \
    -top

set wrapper_files [
    glob \
        -nocomplain \
        [file join \
            $project_dir \
            "${project_name}.gen" \
            "sources_1" \
            "bd" \
            $bd_name \
            "hdl" \
            "${bd_name}_wrapper.v"]
]

if {[llength $wrapper_files] != 1} {
    summary_puts $summary_file \
        "ERROR: generated block-design wrapper was not found"

    close $summary_file
    exit 5
}

add_files \
    -norecurse \
    [lindex $wrapper_files 0]

set_property \
    top \
    "${bd_name}_wrapper" \
    [current_fileset]

update_compile_order \
    -fileset sources_1

set_property \
    strategy \
    Flow_PerfOptimized_high \
    [get_runs synth_1]

set implementation_strategy \
    Performance_ExplorePostRoutePhysOpt

set_property \
    strategy \
    $implementation_strategy \
    [get_runs impl_1]

summary_puts $summary_file \
    "implementation_strategy=$implementation_strategy"

launch_runs \
    synth_1 \
    -jobs 1

wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    summary_puts $summary_file \
        "ERROR: synthesis failed: [get_property STATUS [get_runs synth_1]]"

    close $summary_file
    exit 6
}

launch_runs \
    impl_1 \
    -to_step write_bitstream \
    -jobs 1

wait_on_run impl_1

set impl_status [
    get_property STATUS [get_runs impl_1]
]

summary_puts $summary_file \
    "impl_status=$impl_status"

if {![string match "*write_bitstream Complete*" $impl_status]} {
    summary_puts $summary_file \
        "ERROR: implementation did not complete bitstream generation"

    close $summary_file
    exit 7
}

open_run impl_1

report_drc \
    -file [file join $build_root "drc.rpt"]

report_utilization \
    -hierarchical \
    -file [file join $build_root "routed_utilization.rpt"]

report_timing_summary \
    -delay_type max \
    -max_paths 50 \
    -file [file join $build_root "routed_timing_summary.rpt"]

report_timing \
    -delay_type max \
    -max_paths 20 \
    -path_type full_clock_expanded \
    -file [file join $build_root "routed_critical_paths.rpt"]

set timing_paths [
    get_timing_paths \
        -quiet \
        -delay_type max \
        -max_paths 1 \
        -nworst 1
]

if {[llength $timing_paths] == 0} {
    summary_puts $summary_file \
        "ERROR: no routed timing path was returned"

    close $summary_file
    exit 8
}

set wns [
    get_property \
        SLACK \
        [lindex $timing_paths 0]
]

set failing_paths [
    get_timing_paths \
        -quiet \
        -delay_type max \
        -slack_lesser_than 0.000 \
        -max_paths 100000
]

set dsp_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == DSP48E1}
    ]
]

set ramb18_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == RAMB18E1}
    ]
]

set ramb36_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME == RAMB36E1}
    ]
]

set lut_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ LUT*}
    ]
]

set register_count [
    llength [
        get_cells \
            -quiet \
            -hierarchical \
            -filter {REF_NAME =~ FD*}
    ]
]

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_WNS_NS=$wns"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_FAILING_PATHS=[llength $failing_paths]"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_LUTS=$lut_count"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_REGISTERS=$register_count"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_DSP48E1=$dsp_count"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_RAMB18E1=$ramb18_count"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_RAMB36E1=$ramb36_count"

if {$dsp_count != 192} {
    summary_puts $summary_file \
        "FAIL: expected exactly 192 DSP48E1 in the fused overlay"

    close $summary_file
    exit 9
}

if {$wns < 0.000} {
    summary_puts $summary_file \
        "FAIL: fused BV-relinearization overlay missed routed timing"

    close $summary_file
    exit 9
}

set impl_directory [
    get_property \
        DIRECTORY \
        [get_runs impl_1]
]

set bit_files [
    glob \
        -nocomplain \
        [file join \
            $impl_directory \
            "*.bit"]
]

if {[llength $bit_files] != 1} {
    summary_puts $summary_file \
        "ERROR: expected one implementation bitstream; found $bit_files"

    close $summary_file
    exit 12
}

set hwh_files [
    glob \
        -nocomplain \
        [file join \
            $project_dir \
            "${project_name}.gen" \
            "sources_1" \
            "bd" \
            $bd_name \
            "hw_handoff" \
            "*.hwh"]
]

if {[llength $hwh_files] != 1} {
    summary_puts $summary_file \
        "ERROR: expected one HWH file; found $hwh_files"

    close $summary_file
    exit 11
}

set deploy_stem [
    file join \
        $deploy_dir \
        "evalmul3_bv_relinearized_dma150"
]

file copy \
    -force \
    [lindex $bit_files 0] \
    "${deploy_stem}.bit"

file copy \
    -force \
    [lindex $hwh_files 0] \
    "${deploy_stem}.hwh"

write_checkpoint \
    -force \
    [file join $build_root "routed.dcp"]

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    [file join \
        $build_root \
        "evalmul3_bv_relinearized_dma150_platform.xsa"]

summary_puts $summary_file \
    "bitstream=${deploy_stem}.bit"

summary_puts $summary_file \
    "hardware_handoff=${deploy_stem}.hwh"

summary_puts $summary_file \
    "PASS: exact fused BV-relinearization dual-clock DMA overlay routed"

summary_puts $summary_file \
    "EVALMUL3_BV_RELINEARIZED_DMA150_BUILD_END"

close $summary_file
exit 0
