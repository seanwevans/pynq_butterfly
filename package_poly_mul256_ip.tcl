set root_dir [file dirname [file normalize [info script]]]
set rtl_dir  [file join $root_dir rtl]
set mem_dir  [file join $root_dir model golden_n256]

set work_dir [
    file join \
        $root_dir \
        vivado \
        package_poly_mul256
]

set project_dir [
    file join \
        $work_dir \
        project
]

set ip_dir [
    file join \
        $root_dir \
        ip \
        poly_mul256_1_0
]

set report_dir [
    file join \
        $root_dir \
        reports \
        poly_mul256
]

set constraint_file [
    file join \
        $work_dir \
        poly_mul256_clock.xdc
]

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

puts ""
puts "============================================================"
puts "POLY_MUL256 PACKAGE AND SYNTHESIS"
puts "============================================================"
puts "Root:    $root_dir"
puts "IP:      $ip_dir"
puts "Reports: $report_dir"

file delete -force $work_dir
file delete -force $ip_dir
file delete -force $report_dir

file mkdir $work_dir
file mkdir [file dirname $ip_dir]
file mkdir $report_dir

create_project \
    -force \
    package_poly_mul256 \
    $project_dir \
    -part xc7z020clg400-1

set_property \
    target_language \
    Verilog \
    [current_project]

set_property \
    simulator_language \
    Mixed \
    [current_project]

catch {
    set_property \
        board_part \
        tul.com.tw:pynq-z2:part0:1.0 \
        [current_project]
}

set rtl_files [list \
    [file join $rtl_dir ntt256_profile_pkg.sv] \
    [file join $rtl_dir modmul_core.sv] \
    [file join $rtl_dir butterfly_core.sv] \
    [file join $rtl_dir ntt256_schedule_core.sv] \
    [file join $rtl_dir ntt256_twiddle_rom.sv] \
    [file join $rtl_dir ntt256_factor_rom.sv] \
    [file join $rtl_dir ntt256_coeff_bram.sv] \
    [file join $rtl_dir ntt256_cyclic_core.sv] \
    [file join $rtl_dir forward_ntt256_core.sv] \
    [file join $rtl_dir inverse_ntt256_core.sv] \
    [file join $rtl_dir pointwise_mul256_core.sv] \
    [file join $rtl_dir poly_mul256_core.sv] \
    [file join $rtl_dir poly_mul256_axi_lite.sv] \
]

set memory_files [list \
    [file join $mem_dir twist_factors.mem] \
    [file join $mem_dir forward_twiddles.mem] \
    [file join $mem_dir inverse_twiddles.mem] \
    [file join $mem_dir inverse_scale_factors.mem] \
]

foreach path [concat $rtl_files $memory_files] {
    require_file $path
}

add_files \
    -norecurse \
    $rtl_files

add_files \
    -norecurse \
    $memory_files

foreach source_file $rtl_files {
    set_property \
        file_type \
        SystemVerilog \
        [get_files [file normalize $source_file]]
}

set_property \
    top \
    poly_mul256_axi_lite \
    [get_filesets sources_1]

set constraint_handle [
    open \
        $constraint_file \
        w
]

puts $constraint_handle {
create_clock -name S_AXI_ACLK -period 10.000 [get_ports S_AXI_ACLK]
}

close $constraint_handle

add_files \
    -fileset constrs_1 \
    -norecurse \
    $constraint_file

update_compile_order \
    -fileset sources_1

puts ""
puts "============================================================"
puts "PACKAGING IP"
puts "============================================================"

ipx::package_project \
    -root_dir $ip_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [
    ipx::current_core
]

set_property vendor        user.org   $core
set_property library       user       $core
set_property name          poly_mul256 $core
set_property version       1.0        $core
set_property core_revision 1          $core

set_property \
    display_name \
    {OpenFHE N=256 Negacyclic Polynomial Multiplier} \
    $core

set_property \
    description \
    {BRAM-backed constant-time AXI4-Lite N=256 negacyclic polynomial multiplier using OpenFHE-derived NTT parameters.} \
    $core

ipx::infer_bus_interfaces \
    xilinx.com:interface:aximm_rtl:1.0 \
    $core

ipx::infer_bus_interfaces \
    xilinx.com:signal:clock_rtl:1.0 \
    $core

ipx::infer_bus_interfaces \
    xilinx.com:signal:reset_rtl:1.0 \
    $core

set axi_interface [
    ipx::get_bus_interfaces \
        S_AXI \
        -of_objects $core
]

if {[llength $axi_interface] != 1} {
    error "Expected one S_AXI interface; found [llength $axi_interface]"
}

set_property \
    interface_mode \
    slave \
    $axi_interface

set clock_interface [
    ipx::get_bus_interfaces \
        S_AXI_ACLK \
        -of_objects $core
]

if {[llength $clock_interface] != 1} {
    error "Expected one S_AXI_ACLK interface"
}

set reset_interface [
    ipx::get_bus_interfaces \
        S_AXI_ARESETN \
        -of_objects $core
]

if {[llength $reset_interface] != 1} {
    error "Expected one S_AXI_ARESETN interface"
}

ipx::associate_bus_interfaces \
    -busif S_AXI \
    -clock S_AXI_ACLK \
    $core

set reset_polarity [
    ipx::get_bus_parameters \
        POLARITY \
        -of_objects $reset_interface
]

if {[llength $reset_polarity] == 0} {
    set reset_polarity [
        ipx::add_bus_parameter \
            POLARITY \
            $reset_interface
    ]
}

set_property \
    value \
    ACTIVE_LOW \
    $reset_polarity

set memory_maps [
    ipx::get_memory_maps \
        S_AXI \
        -of_objects $core
]

if {[llength $memory_maps] == 0} {
    set memory_map [
        ipx::add_memory_map \
            S_AXI \
            $core
    ]
} else {
    set memory_map [
        lindex \
            $memory_maps \
            0
    ]
}

set address_blocks [
    ipx::get_address_blocks \
        -of_objects $memory_map
]

if {[llength $address_blocks] == 0} {
    set address_block [
        ipx::add_address_block \
            registers \
            $memory_map
    ]
} else {
    set address_block [
        lindex \
            $address_blocks \
            0
    ]
}

set_property base_address 0        $address_block
set_property range        65536    $address_block
set_property width        32       $address_block
set_property usage        register $address_block

set_property \
    slave_memory_map_ref \
    S_AXI \
    $axi_interface

ipx::create_xgui_files $core
ipx::update_checksums $core

set integrity_result [
    ipx::check_integrity \
        -quiet \
        $core
]

puts "IP integrity result: $integrity_result"

ipx::save_core $core

set_property \
    ip_repo_paths \
    [list $ip_dir] \
    [current_project]

update_ip_catalog

puts ""
puts "============================================================"
puts "RUNNING OUT-OF-CONTEXT SYNTHESIS"
puts "============================================================"

reset_run synth_1

launch_runs \
    synth_1 \
    -jobs 8

wait_on_run synth_1

set synth_status [
    get_property \
        STATUS \
        [get_runs synth_1]
]

puts "Synthesis status: $synth_status"

if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed: $synth_status"
}

open_run synth_1

set utilization_report [
    file join \
        $report_dir \
        poly_mul256_utilization.rpt
]

set timing_report [
    file join \
        $report_dir \
        poly_mul256_timing.rpt
]

set hierarchy_report [
    file join \
        $report_dir \
        poly_mul256_hierarchical_utilization.rpt
]

report_utilization \
    -file $utilization_report

report_utilization \
    -hierarchical \
    -hierarchical_depth 5 \
    -file $hierarchy_report

report_timing_summary \
    -file $timing_report

set ramb18_count [
    llength [
        get_cells \
            -hierarchical \
            -quiet \
            -filter {REF_NAME == RAMB18E1}
    ]
]

set ramb36_count [
    llength [
        get_cells \
            -hierarchical \
            -quiet \
            -filter {REF_NAME == RAMB36E1}
    ]
]

set dsp_count [
    llength [
        get_cells \
            -hierarchical \
            -quiet \
            -filter {REF_NAME == DSP48E1}
    ]
]

puts ""
puts "============================================================"
puts "PACKAGE AND SYNTHESIS COMPLETE"
puts "============================================================"
puts "VLNV: user.org:user:poly_mul256:1.0"
puts "IP directory: $ip_dir"
puts "Component: [file join $ip_dir component.xml]"
puts "Synthesis: $synth_status"
puts "RAMB18E1 cells: $ramb18_count"
puts "RAMB36E1 cells: $ramb36_count"
puts "DSP48E1 cells:  $dsp_count"
puts "Utilization: $utilization_report"
puts "Hierarchical utilization: $hierarchy_report"
puts "Timing: $timing_report"
puts "============================================================"
puts ""

close_project
