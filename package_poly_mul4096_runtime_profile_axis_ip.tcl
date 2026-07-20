set root_dir [file dirname [file normalize [info script]]]

set rtl_dir [file join $root_dir rtl]

set ip_root \
    [file join $root_dir ip poly_mul4096_runtime_profile_axis_1_0]

set stage_dir \
    [file join $ip_root staged_sources]

set project_dir \
    [file join $root_dir vivado package_poly_mul4096_runtime_profile_axis]

set part_name xc7z020clg400-1
set top_name poly_mul4096_runtime_profile_axis_core

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

proc set_bus_parameter_value {bus name value} {
    set parameter \
        [ipx::get_bus_parameters -quiet $name -of_objects $bus]

    if {[llength $parameter] == 0} {
        set parameter \
            [ipx::add_bus_parameter $name $bus]
    }

    set_property value $value $parameter
}

file delete -force $ip_root
file delete -force $project_dir

file mkdir $stage_dir
file mkdir $project_dir

set rtl_names [list \
    ntt4096_profile_pkg.sv \
    modmul_core.sv \
    butterfly_core.sv \
    butterfly_dif_core.sv \
    ntt4096_schedule_core.sv \
    ntt4096_dif_schedule_core.sv \
    ntt4096_coeff_bram.sv \
    ntt4096_profile_bram.sv \
    poly_mul4096_runtime_profile_core.sv \
    poly_mul4096_runtime_profile_axis_core.sv \
]

set staged_rtl_files [list]

foreach name $rtl_names {
    set source \
        [file join $rtl_dir $name]

    require_file $source

    set destination \
        [file join $stage_dir $name]

    file copy -force \
        $source \
        $destination

    lappend staged_rtl_files \
        $destination
}

create_project \
    -force \
    package_poly_mul4096_runtime_profile_axis \
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
    $staged_rtl_files

foreach path $staged_rtl_files {
    set_property \
        file_type \
        SystemVerilog \
        [get_files [file normalize $path]]
}

set_property \
    top \
    $top_name \
    [get_filesets sources_1]

update_compile_order \
    -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor user.org \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core \
    [ipx::current_core]

set_property \
    name \
    poly_mul4096_runtime_profile_axis \
    $core

set_property \
    display_name \
    {Runtime-Profile N=4096 Negacyclic Polynomial Multiplier AXI4-Stream} \
    $core

set_property \
    description \
    {Runtime-programmable constant-time N=4096 negacyclic polynomial multiplier with streamed profile loading and streamed products.} \
    $core

set_property vendor user.org $core
set_property library user $core
set_property version 1.0 $core
set_property core_revision 1 $core

set_property \
    supported_families \
    {zynq Production} \
    $core

if {
    [llength \
        [ipx::get_bus_interfaces -quiet s_axis -of_objects $core]
    ] == 0
} {
    ipx::infer_bus_interface \
        s_axis \
        xilinx.com:interface:axis_rtl:1.0 \
        $core
}

if {
    [llength \
        [ipx::get_bus_interfaces -quiet m_axis -of_objects $core]
    ] == 0
} {
    ipx::infer_bus_interface \
        m_axis \
        xilinx.com:interface:axis_rtl:1.0 \
        $core
}

if {
    [llength \
        [ipx::get_bus_interfaces -quiet clk -of_objects $core]
    ] == 0
} {
    ipx::infer_bus_interface \
        clk \
        xilinx.com:signal:clock_rtl:1.0 \
        $core
}

if {
    [llength \
        [ipx::get_bus_interfaces -quiet reset_n -of_objects $core]
    ] == 0
} {
    ipx::infer_bus_interface \
        reset_n \
        xilinx.com:signal:reset_rtl:1.0 \
        $core
}

set s_axis \
    [ipx::get_bus_interfaces s_axis -of_objects $core]

set m_axis \
    [ipx::get_bus_interfaces m_axis -of_objects $core]

set clk_bus \
    [ipx::get_bus_interfaces clk -of_objects $core]

set reset_bus \
    [ipx::get_bus_interfaces reset_n -of_objects $core]

set_property \
    interface_mode \
    slave \
    $s_axis

set_property \
    interface_mode \
    master \
    $m_axis

set_bus_parameter_value \
    $s_axis \
    TDATA_NUM_BYTES \
    4

set_bus_parameter_value \
    $s_axis \
    HAS_TLAST \
    1

set_bus_parameter_value \
    $m_axis \
    TDATA_NUM_BYTES \
    4

set_bus_parameter_value \
    $m_axis \
    HAS_TLAST \
    1

set_bus_parameter_value \
    $clk_bus \
    ASSOCIATED_BUSIF \
    {s_axis:m_axis}

set_bus_parameter_value \
    $clk_bus \
    ASSOCIATED_RESET \
    reset_n

set_bus_parameter_value \
    $reset_bus \
    POLARITY \
    ACTIVE_LOW

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

set integrity_result \
    [ipx::check_integrity -quiet $core]

puts ""
puts "============================================================"
puts "N=4096 RUNTIME-PROFILE AXI4-STREAM IP PACKAGING COMPLETE"
puts "============================================================"
puts "IP root:             [file normalize $ip_root]"
puts "VLNV:                user.org:user:poly_mul4096_runtime_profile_axis:1.0"
puts "Integrity:           $integrity_result"
puts "Profile frame:       16384 x 32-bit words"
puts "Product input frame: 8193 x 32-bit words"
puts "Product output:      4096 x 32-bit words"
puts "Core cycles:         1339394"
puts "============================================================"
puts ""

close_project
