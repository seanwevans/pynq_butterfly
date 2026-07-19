set root_dir [file dirname [file normalize [info script]]]
set rtl_dir  [file join $root_dir rtl]

set work_dir [file join $root_dir vivado package_poly_mul16]
set ip_dir   [file join $root_dir ip poly_mul16_1_0]

puts "Project root: $root_dir"
puts "RTL directory: $rtl_dir"
puts "IP output: $ip_dir"

file delete -force $work_dir
file delete -force $ip_dir

file mkdir $work_dir
file mkdir [file dirname $ip_dir]

create_project \
    -force \
    package_poly_mul16 \
    [file join $work_dir project] \
    -part xc7z020clg400-1

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

catch {
    set_property \
        board_part \
        tul.com.tw:pynq-z2:part0:1.0 \
        [current_project]
}

set source_files [list \
    [file join $rtl_dir modmul_core.sv] \
    [file join $rtl_dir butterfly_core.sv] \
    [file join $rtl_dir ntt16_core.sv] \
    [file join $rtl_dir forward_ntt16_core.sv] \
    [file join $rtl_dir pointwise_mul16_core.sv] \
    [file join $rtl_dir intt16_cyclic_core.sv] \
    [file join $rtl_dir inverse_ntt16_core.sv] \
    [file join $rtl_dir poly_mul16_core.sv] \
    [file join $rtl_dir poly_mul16_axi_lite.sv] \
]

foreach source_file $source_files {
    if {![file exists $source_file]} {
        error "Missing source file: $source_file"
    }
}

add_files -norecurse $source_files

foreach source_file $source_files {
    set_property \
        file_type \
        SystemVerilog \
        [get_files [file normalize $source_file]]
}

set_property \
    top \
    poly_mul16_axi_lite \
    [get_filesets sources_1]

update_compile_order -fileset sources_1

puts "Packaging RTL project..."

ipx::package_project \
    -root_dir $ip_dir \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]

set_property vendor       user.org $core
set_property library      user     $core
set_property name         poly_mul16 $core
set_property version      1.0      $core
set_property core_revision 1       $core

set_property \
    display_name \
    {OpenFHE N=16 Negacyclic Polynomial Multiplier} \
    $core

set_property \
    description \
    {AXI4-Lite N=16 negacyclic polynomial multiplier using an OpenFHE-derived modulus and NTT roots.} \
    $core

set_property \
    company_url \
    {https://github.com/} \
    $core

puts "Inferring AXI, clock, and reset interfaces..."

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
    error "Expected one inferred S_AXI interface; found [llength $axi_interface]"
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

set_property value ACTIVE_LOW $reset_polarity

puts "Creating the 64 KiB AXI address space..."

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
    set memory_map [lindex $memory_maps 0]
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
    set address_block [lindex $address_blocks 0]
}

set_property base_address 0      $address_block
set_property range        65536  $address_block
set_property width        32     $address_block
set_property usage        register $address_block

catch {
    set_property range_dependency {} $address_block
}

set_property \
    slave_memory_map_ref \
    S_AXI \
    $axi_interface

ipx::create_xgui_files $core
ipx::update_checksums $core

puts "Checking packaged-IP integrity..."

set integrity_messages [
    ipx::check_integrity \
        -quiet \
        $core
]

if {$integrity_messages ne ""} {
    puts $integrity_messages
}

ipx::save_core $core

set_property \
    ip_repo_paths \
    [list $ip_dir] \
    [current_project]

update_ip_catalog

puts ""
puts "============================================================"
puts "PACKAGING COMPLETE"
puts "VLNV: user.org:user:poly_mul16:1.0"
puts "IP directory: $ip_dir"
puts "Component file: [file join $ip_dir component.xml]"
puts "============================================================"
puts ""

close_project
