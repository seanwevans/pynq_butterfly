set source_project "F:/repos/pynq_poly_mul256_dma/pynq_poly_mul256_dma.xpr"

set clone_name "pynq_poly_mul256_dma_batch32"
set clone_dir "F:/repos/pynq_poly_mul256_dma_batch32"
set clone_project [file join $clone_dir "${clone_name}.xpr"]

set batch_ip_repo "F:/repos/pynq_butterfly/ip/poly_mul256_axis_batch_1_0"
set deploy_dir "F:/repos/pynq_butterfly/deploy"
set report_dir "F:/repos/pynq_butterfly/reports/pynq_poly_mul256_dma_batch32"

set batch_vlnv "user.org:user:poly_mul256_axis_batch:1.0"
set batch_instance "poly_mul256_axis_batch_0"

set old_axis_instance "poly_mul256_axis_0"
set dma_instance "axi_dma_0"

set batch_products 32
set dma_length_width 23

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

require_file $source_project "Source DMA project"
require_file [file join $batch_ip_repo component.xml] "Packaged batch IP"

puts ""
puts "============================================================"
puts "CREATING BATCH-32 DMA OVERLAY PROJECT"
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
puts "REGISTERING BATCH IP"
puts "============================================================"

set existing_repositories [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $existing_repositories $batch_ip_repo] < 0} {
    set_property ip_repo_paths [concat $existing_repositories [list $batch_ip_repo]] [current_project]
}
update_ip_catalog

require_one [get_ipdefs -all -quiet $batch_vlnv] "batch IP definition"

set bd_file [require_one [get_files -quiet *.bd] "block-design file"]
open_bd_design $bd_file
set bd_name [current_bd_design]

set dma [require_one [get_bd_cells -quiet $dma_instance] "AXI DMA"]
set fabric_clock [require_one [get_bd_pins -quiet processing_system7_0/FCLK_CLK0] "FCLK_CLK0"]
set peripheral_resetn [require_one [get_bd_pins -quiet rst_ps7_0_100M/peripheral_aresetn] "peripheral_aresetn"]

puts ""
puts "============================================================"
puts "WIDENING DMA LENGTH REGISTER"
puts "============================================================"

set_property CONFIG.c_sg_length_width $dma_length_width $dma

puts "DMA length width: [get_property CONFIG.c_sg_length_width $dma] bits"

puts ""
puts "============================================================"
puts "REPLACING SINGLE-PRODUCT STREAM CORE"
puts "============================================================"

set old_axis [get_bd_cells -quiet $old_axis_instance]
if {[llength $old_axis] == 1} {
    delete_bd_objs $old_axis
} elseif {[llength $old_axis] > 1} {
    error "Found multiple old stream cores: $old_axis"
}

if {[llength [get_bd_cells -quiet $batch_instance]] != 0} {
    error "Cell already exists unexpectedly: $batch_instance"
}

set batch_core [create_bd_cell -type ip -vlnv $batch_vlnv $batch_instance]

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/M_AXIS_MM2S] "DMA M_AXIS_MM2S"] \
    [require_one [get_bd_intf_pins -quiet ${batch_instance}/S_AXIS] "batch S_AXIS"]

connect_bd_intf_net \
    [require_one [get_bd_intf_pins -quiet ${batch_instance}/M_AXIS] "batch M_AXIS"] \
    [require_one [get_bd_intf_pins -quiet ${dma_instance}/S_AXIS_S2MM] "DMA S_AXIS_S2MM"]

connect_bd_net \
    $fabric_clock \
    [require_one [get_bd_pins -quiet ${batch_instance}/aclk] "batch aclk"]

connect_bd_net \
    $peripheral_resetn \
    [require_one [get_bd_pins -quiet ${batch_instance}/aresetn] "batch aresetn"]

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

set utilization_report [file join $report_dir pynq_poly_mul256_dma_batch32_utilization.rpt]
set timing_report [file join $report_dir pynq_poly_mul256_dma_batch32_timing.rpt]
set hierarchical_report [file join $report_dir pynq_poly_mul256_dma_batch32_hierarchical_utilization.rpt]

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

set deploy_bit [file join $deploy_dir pynq_poly_mul256_dma_batch32.bit]
set deploy_hwh [file join $deploy_dir pynq_poly_mul256_dma_batch32.hwh]

file copy -force $bit_path $deploy_bit
file copy -force $hwh_path $deploy_hwh

set manifest_path [file join $deploy_dir pynq_poly_mul256_dma_batch32.txt]
set manifest [open $manifest_path w]

puts $manifest "project=$clone_project"
puts $manifest "block_design=$bd_name"
puts $manifest "top=$top_name"

puts $manifest "axi_dma_base=0x40400000"
puts $manifest "dma_mode=simple"
puts $manifest "dma_memory_port=S_AXI_HP0"
puts $manifest "dma_stream_width_bits=32"
puts $manifest "dma_length_width_bits=$dma_length_width"

puts $manifest "batch_products=$batch_products"
puts $manifest "input_words_per_product=512"
puts $manifest "input_bytes_per_product=2048"
puts $manifest "output_words_per_product=256"
puts $manifest "output_bytes_per_product=1024"
puts $manifest "batch_input_words=[expr {$batch_products * 512}]"
puts $manifest "batch_input_bytes=[expr {$batch_products * 2048}]"
puts $manifest "batch_output_words=[expr {$batch_products * 256}]"
puts $manifest "batch_output_bytes=[expr {$batch_products * 1024}]"

puts $manifest "poly_mul256_n=256"
puts $manifest "poly_mul256_modulus=1073692673"
puts $manifest "poly_mul256_core_cycles=93713"
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
puts "BATCH-32 DMA BUILD COMPLETE"
puts "============================================================"
puts "Project:       $clone_project"
puts "Top:           $top_name"
puts "Bitstream:     $deploy_bit"
puts "HWH:           $deploy_hwh"
puts "Manifest:      $manifest_path"
puts "Batch:         $batch_products products"
puts "Input bytes:   [expr {$batch_products * 2048}]"
puts "Output bytes:  [expr {$batch_products * 1024}]"
puts "DMA length:    $dma_length_width bits"
puts "Utilization:   $utilization_report"
puts "Timing:        $timing_report"
puts "============================================================"
puts ""

close_project
