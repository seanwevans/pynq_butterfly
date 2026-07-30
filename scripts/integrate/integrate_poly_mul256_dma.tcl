set source_project "F:/repos/pynq_poly_mul256/pynq_poly_mul256.xpr"

set clone_name "pynq_poly_mul256_dma"
set clone_dir "F:/repos/pynq_poly_mul256_dma"
set clone_project [file join $clone_dir "${clone_name}.xpr"]

set axis_ip_repo "F:/repos/pynq_butterfly/ip/poly_mul256_axis_1_0"
set deploy_dir "F:/repos/pynq_butterfly/deploy/pynq_poly_mul256_dma"
set report_dir "F:/repos/pynq_butterfly/reports/pynq_poly_mul256_dma"

set axis_vlnv "user.org:user:poly_mul256_axis:1.0"
set dma_vlnv "xilinx.com:ip:axi_dma:7.1"
set interconnect_vlnv "xilinx.com:ip:axi_interconnect:2.1"

set axis_instance "poly_mul256_axis_0"
set dma_instance "axi_dma_0"
set memory_interconnect_instance "axi_dma_mem_interconnect"

set dma_control_offset 0x40400000
set dma_control_range 0x00010000

proc require_one {objects description} {
    if {[llength $objects] != 1} {
        error "Expected one $description; found [llength $objects]: $objects"
    }
    return [lindex $objects 0]
}

proc require_file {path description} {
    if {![file exists $path]} {
        error "$description was not found: $path"
    }
}

proc find_files_recursive {root pattern} {
    set matches {}
    foreach item [glob -nocomplain -directory $root *] {
        if {[file isdirectory $item]} {
            set matches [concat $matches [find_files_recursive $item $pattern]]
        } elseif {[string match $pattern [file tail $item]]} {
            lappend matches $item
        }
    }
    return $matches
}

require_file $source_project "Source project"
require_file [file join $axis_ip_repo component.xml] "Packaged AXI-Stream IP"

puts ""
puts "============================================================"
puts "CREATING DMA OVERLAY PROJECT"
puts "============================================================"

file delete -force $clone_dir
file delete -force $report_dir
file mkdir $report_dir

open_project $source_project
save_project_as -force $clone_name $clone_dir
close_project

require_file $clone_project "Cloned project"
open_project $clone_project

puts "Project: [get_property NAME [current_project]]"
puts "Part:    [get_property PART [current_project]]"
puts "Board:   [get_property BOARD_PART [current_project]]"

puts ""
puts "============================================================"
puts "REGISTERING AXI-STREAM IP"
puts "============================================================"

set existing_repositories [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $existing_repositories $axis_ip_repo] < 0} {
    set_property ip_repo_paths [concat $existing_repositories [list $axis_ip_repo]] [current_project]
}
update_ip_catalog

require_one [get_ipdefs -all -quiet $axis_vlnv] "poly_mul256_axis IP definition"
require_one [get_ipdefs -all -quiet $dma_vlnv] "AXI DMA IP definition"
require_one [get_ipdefs -all -quiet $interconnect_vlnv] "AXI Interconnect IP definition"

set bd_file [require_one [get_files -quiet *.bd] "block-design file"]
open_bd_design $bd_file
set bd_name [current_bd_design]

puts "Block design: $bd_name"

set processing_system [require_one [get_bd_cells -quiet processing_system7_0] "processing_system7_0"]
set control_interconnect [require_one [get_bd_cells -quiet ps7_0_axi_periph] "PS AXI peripheral interconnect"]
set fabric_clock [require_one [get_bd_pins -quiet processing_system7_0/FCLK_CLK0] "FCLK_CLK0"]
set peripheral_resetn [require_one [get_bd_pins -quiet rst_ps7_0_100M/peripheral_aresetn] "peripheral_aresetn"]

puts ""
puts "============================================================"
puts "ENABLING ZYNQ HIGH-PERFORMANCE PORT"
puts "============================================================"

set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {1}] $processing_system

set hp0_interface [require_one [get_bd_intf_pins -quiet processing_system7_0/S_AXI_HP0] "Zynq S_AXI_HP0 interface"]
set hp0_clock [require_one [get_bd_pins -quiet processing_system7_0/S_AXI_HP0_ACLK] "Zynq S_AXI_HP0_ACLK"]

puts ""
puts "============================================================"
puts "ADDING DMA CONTROL MASTER PORT"
puts "============================================================"

set_property CONFIG.NUM_MI 5 $control_interconnect

set control_m04 [require_one [get_bd_intf_pins -quiet ps7_0_axi_periph/M04_AXI] "ps7_0_axi_periph M04_AXI"]
set control_m04_clock [require_one [get_bd_pins -quiet ps7_0_axi_periph/M04_ACLK] "ps7_0_axi_periph M04_ACLK"]
set control_m04_resetn [require_one [get_bd_pins -quiet ps7_0_axi_periph/M04_ARESETN] "ps7_0_axi_periph M04_ARESETN"]

puts ""
puts "============================================================"
puts "CREATING AXI DMA"
puts "============================================================"

if {[llength [get_bd_cells -quiet $dma_instance]] != 0} {
    error "Cell already exists unexpectedly: $dma_instance"
}

set dma [create_bd_cell -type ip -vlnv $dma_vlnv $dma_instance]

set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_addr_width {32} \
] $dma

puts ""
puts "============================================================"
puts "CREATING STREAMING POLYNOMIAL CORE"
puts "============================================================"

if {[llength [get_bd_cells -quiet $axis_instance]] != 0} {
    error "Cell already exists unexpectedly: $axis_instance"
}

create_bd_cell -type ip -vlnv $axis_vlnv $axis_instance

puts ""
puts "============================================================"
puts "CREATING DMA MEMORY INTERCONNECT"
puts "============================================================"

if {[llength [get_bd_cells -quiet $memory_interconnect_instance]] != 0} {
    error "Cell already exists unexpectedly: $memory_interconnect_instance"
}

set memory_interconnect [create_bd_cell -type ip -vlnv $interconnect_vlnv $memory_interconnect_instance]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $memory_interconnect

puts ""
puts "============================================================"
puts "CONNECTING DMA CONTROL AND STREAM INTERFACES"
puts "============================================================"

connect_bd_intf_net \
    $control_m04 \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/S_AXI_LITE] "DMA S_AXI_LITE"]

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/M_AXIS_MM2S] "DMA M_AXIS_MM2S"] \
    [require_one [get_bd_intf_pins -quiet ${axis_instance}/S_AXIS] "polynomial S_AXIS"]

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${axis_instance}/M_AXIS] "polynomial M_AXIS"] \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/S_AXIS_S2MM] "DMA S_AXIS_S2MM"]

puts ""
puts "============================================================"
puts "CONNECTING DMA MEMORY MASTERS TO HP0"
puts "============================================================"

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/M_AXI_MM2S] "DMA M_AXI_MM2S"] \
    [require_one [get_bd_intf_pins -quiet ${memory_interconnect_instance}/S00_AXI] "memory interconnect S00_AXI"]

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/M_AXI_S2MM] "DMA M_AXI_S2MM"] \
    [require_one [get_bd_intf_pins -quiet ${memory_interconnect_instance}/S01_AXI] "memory interconnect S01_AXI"]

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${memory_interconnect_instance}/M00_AXI] "memory interconnect M00_AXI"] \
    $hp0_interface

puts ""
puts "============================================================"
puts "CONNECTING CLOCKS"
puts "============================================================"

connect_bd_net \
    $fabric_clock \
    $control_m04_clock \
    $hp0_clock \
    [require_one [get_bd_pins -quiet ${dma_instance}/s_axi_lite_aclk] "DMA s_axi_lite_aclk"] \
    [require_one [get_bd_pins -quiet ${dma_instance}/m_axi_mm2s_aclk] "DMA m_axi_mm2s_aclk"] \
    [require_one [get_bd_pins -quiet ${dma_instance}/m_axi_s2mm_aclk] "DMA m_axi_s2mm_aclk"] \
    [require_one [get_bd_pins -quiet ${axis_instance}/aclk] "polynomial aclk"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/ACLK] "memory interconnect ACLK"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/S00_ACLK] "memory interconnect S00_ACLK"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/S01_ACLK] "memory interconnect S01_ACLK"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/M00_ACLK] "memory interconnect M00_ACLK"]

puts ""
puts "============================================================"
puts "CONNECTING RESETS"
puts "============================================================"

connect_bd_net \
    $peripheral_resetn \
    $control_m04_resetn \
    [require_one [get_bd_pins -quiet ${dma_instance}/axi_resetn] "DMA axi_resetn"] \
    [require_one [get_bd_pins -quiet ${axis_instance}/aresetn] "polynomial aresetn"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/ARESETN] "memory interconnect ARESETN"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/S00_ARESETN] "memory interconnect S00_ARESETN"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/S01_ARESETN] "memory interconnect S01_ARESETN"] \
    [require_one [get_bd_pins -quiet ${memory_interconnect_instance}/M00_ARESETN] "memory interconnect M00_ARESETN"]

puts ""
puts "============================================================"
puts "ASSIGNING ADDRESS SPACES"
puts "============================================================"

set dma_register_segment [require_one [get_bd_addr_segs -quiet ${dma_instance}/S_AXI_LITE/Reg] "DMA register segment"]

assign_bd_address \
    -offset $dma_control_offset \
    -range $dma_control_range \
    $dma_register_segment

# Create the DDR mappings for both DMA memory-master address spaces.
assign_bd_address

puts ""
puts "DMA control mappings:"
foreach segment [get_bd_addr_segs -quiet processing_system7_0/Data/*axi_dma_0*] {
    puts [format "%-80s offset=%-12s range=%s" \
        $segment \
        [get_property OFFSET $segment] \
        [get_property RANGE $segment]]
}

set mm2s_space [require_one [get_bd_addr_spaces -quiet ${dma_instance}/Data_MM2S] "DMA MM2S address space"]
set s2mm_space [require_one [get_bd_addr_spaces -quiet ${dma_instance}/Data_S2MM] "DMA S2MM address space"]

puts ""
puts "MM2S memory mappings:"
foreach segment [get_bd_addr_segs -quiet -of_objects $mm2s_space] {
    puts [format "%-80s offset=%-12s range=%s" \
        $segment \
        [get_property OFFSET $segment] \
        [get_property RANGE $segment]]
}

puts ""
puts "S2MM memory mappings:"
foreach segment [get_bd_addr_segs -quiet -of_objects $s2mm_space] {
    puts [format "%-80s offset=%-12s range=%s" \
        $segment \
        [get_property OFFSET $segment] \
        [get_property RANGE $segment]]
}

puts ""
puts "============================================================"
puts "VALIDATING BLOCK DESIGN"
puts "============================================================"

validate_bd_design
save_bd_design
generate_target all $bd_file

set wrapper_files [get_files -quiet *${bd_name}_wrapper.v]
if {[llength $wrapper_files] == 0} {
    set wrapper_path [make_wrapper -files $bd_file -top]
    add_files -norecurse $wrapper_path
}

update_compile_order -fileset sources_1
set top_name [get_property TOP [get_filesets sources_1]]

puts "Top module: $top_name"

puts ""
puts "============================================================"
puts "RUNNING SYNTHESIS"
puts "============================================================"

reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synthesis_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synthesis_status"

if {![string match "*Complete*" $synthesis_status]} {
    error "Synthesis failed: $synthesis_status"
}

puts ""
puts "============================================================"
puts "RUNNING IMPLEMENTATION AND BITSTREAM"
puts "============================================================"

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set implementation_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $implementation_status"

if {![string match "*Complete*" $implementation_status]} {
    error "Implementation failed: $implementation_status"
}

open_run impl_1

set utilization_report [file join $report_dir pynq_poly_mul256_dma_utilization.rpt]
set timing_report [file join $report_dir pynq_poly_mul256_dma_timing.rpt]
set hierarchical_report [file join $report_dir pynq_poly_mul256_dma_hierarchical_utilization.rpt]

report_utilization -file $utilization_report
report_utilization -hierarchical -hierarchical_depth 5 -file $hierarchical_report
report_timing_summary -file $timing_report

puts ""
puts "============================================================"
puts "COLLECTING DEPLOYMENT ARTIFACTS"
puts "============================================================"

file mkdir $deploy_dir

set expected_bit [file join $clone_dir "${clone_name}.runs" impl_1 "${top_name}.bit"]
set bit_path $expected_bit

if {![file exists $bit_path]} {
    set implementation_bits {}
    foreach candidate [find_files_recursive $clone_dir "*.bit"] {
        if {[string match "*impl_1*" $candidate]} {
            lappend implementation_bits $candidate
        }
    }
    set bit_path [require_one $implementation_bits "implementation bitstream"]
}

set expected_hwh [file join \
    $clone_dir \
    "${clone_name}.gen" \
    sources_1 \
    bd \
    $bd_name \
    hw_handoff \
    "${bd_name}.hwh"]

set hwh_path $expected_hwh

if {![file exists $hwh_path]} {
    set hwh_candidates [find_files_recursive $clone_dir "${bd_name}.hwh"]
    set hwh_path [require_one $hwh_candidates "hardware handoff file"]
}

set deploy_bit [file join $deploy_dir pynq_poly_mul256_dma.bit]
set deploy_hwh [file join $deploy_dir pynq_poly_mul256_dma.hwh]

file copy -force $bit_path $deploy_bit
file copy -force $hwh_path $deploy_hwh

set manifest_path [file join $deploy_dir manifest.txt]
set manifest [open $manifest_path w]

puts $manifest "project=$clone_project"
puts $manifest "block_design=$bd_name"
puts $manifest "top=$top_name"

puts $manifest "modadd_base=0x43C00000"
puts $manifest "modmul_base=0x43C10000"
puts $manifest "poly_mul16_base=0x43C20000"
puts $manifest "poly_mul256_axilite_base=0x43C30000"
puts $manifest "axi_dma_base=0x40400000"

puts $manifest "dma_mode=simple"
puts $manifest "dma_memory_port=S_AXI_HP0"
puts $manifest "dma_stream_width_bits=32"
puts $manifest "dma_input_words=512"
puts $manifest "dma_input_bytes=2048"
puts $manifest "dma_output_words=256"
puts $manifest "dma_output_bytes=1024"

puts $manifest "poly_mul256_n=256"
puts $manifest "poly_mul256_modulus=1073692673"
puts $manifest "poly_mul256_core_cycles=159249"
puts $manifest "poly_mul256_multiplications=4096"

puts $manifest "bitstream=$deploy_bit"
puts $manifest "hwh=$deploy_hwh"
puts $manifest "utilization_report=$utilization_report"
puts $manifest "hierarchical_report=$hierarchical_report"
puts $manifest "timing_report=$timing_report"
puts $manifest "synthesis_status=$synthesis_status"
puts $manifest "implementation_status=$implementation_status"

close $manifest

puts ""
puts "============================================================"
puts "DMA BUILD COMPLETE"
puts "============================================================"
puts "Project:     $clone_project"
puts "Top:         $top_name"
puts "Bitstream:   $deploy_bit"
puts "HWH:         $deploy_hwh"
puts "Manifest:    $manifest_path"
puts "Utilization: $utilization_report"
puts "Timing:      $timing_report"
puts "DMA base:    0x40400000"
puts "DMA memory:  processing_system7_0/S_AXI_HP0"
puts "============================================================"
puts ""

close_project