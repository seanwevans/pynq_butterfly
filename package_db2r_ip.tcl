set source_root F:/repos/pynq_butterfly
set rtl_dir [file join $source_root rtl]

set ip_repo F:/v/ip
set ip_root [file join $ip_repo db2r_1_0]
set stage_dir [file join $ip_root src]
set project_dir F:/v/pkg_db2r

set part_name xc7z020clg400-1
set top_name poly_mul4096_dual_butterfly_two_tower_buffered_axis_core

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

file delete -force $ip_root
file delete -force $project_dir

file mkdir $stage_dir
file mkdir $project_dir

set rtl_names [list \
    modmul_core.sv \
    ntt4096_coeff_bank_1024x32.sv \
    ntt4096_four_bank_coeff_store.sv \
    ntt4096_profile_bram_dual_read.sv \
    ntt4096_paired_schedule_core.sv \
    ntt4096_dual_mode_butterfly_core.sv \
    poly_mul4096_dual_butterfly_runtime_profile_handoff_core.sv \
    poly_mul4096_dual_butterfly_runtime_profile_buffered_axis_core.sv \
    poly_mul4096_dual_butterfly_two_tower_buffered_axis_core.sv \
]

set staged_files [list]

foreach name $rtl_names {
    set source [file join $rtl_dir $name]
    require_file $source

    set destination [file join $stage_dir $name]

    file copy -force \
        $source \
        $destination

    lappend staged_files \
        $destination
}

create_project \
    -force \
    pkg \
    $project_dir \
    -part $part_name

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

add_files \
    -norecurse \
    $staged_files

foreach path $staged_files {
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

set core [ipx::current_core]

set_property name db2r $core
set_property display_name {Buffered-Handoff Dual-Butterfly Two-Tower N=4096 Multiplier} $core
set_property description {Runtime-profiled two-tower N=4096 negacyclic multiplier with one-product operand prefetch, four-wide result/refill handoff, one result buffer per tower, and 64-bit AXI4-Stream batching.} $core
set_property vendor user.org $core
set_property library user $core
set_property version 1.0 $core
set_property core_revision 1 $core
set_property supported_families {zynq Production} $core

foreach specification {
    {s_axis xilinx.com:interface:axis_rtl:1.0}
    {m_axis xilinx.com:interface:axis_rtl:1.0}
    {clk xilinx.com:signal:clock_rtl:1.0}
    {reset_n xilinx.com:signal:reset_rtl:1.0}
} {
    lassign $specification interface_name interface_vlnv

    if {
        [llength \
            [ipx::get_bus_interfaces \
                -quiet \
                $interface_name \
                -of_objects $core \
            ] \
        ] == 0
    } {
        ipx::infer_bus_interface \
            $interface_name \
            $interface_vlnv \
            $core
    }
}

set s_axis [ipx::get_bus_interfaces s_axis -of_objects $core]
set m_axis [ipx::get_bus_interfaces m_axis -of_objects $core]
set clk_bus [ipx::get_bus_interfaces clk -of_objects $core]
set reset_bus [ipx::get_bus_interfaces reset_n -of_objects $core]

set_property interface_mode slave $s_axis
set_property interface_mode master $m_axis

proc set_bus_parameter_value {bus name value} {
    set parameter \
        [ipx::get_bus_parameters \
            -quiet \
            $name \
            -of_objects $bus \
        ]

    if {[llength $parameter] == 0} {
        set parameter \
            [ipx::add_bus_parameter \
                $name \
                $bus \
            ]
    }

    set_property value $value $parameter
}

set_bus_parameter_value $s_axis TDATA_NUM_BYTES 8
set_bus_parameter_value $s_axis HAS_TLAST 1

set_bus_parameter_value $m_axis TDATA_NUM_BYTES 8
set_bus_parameter_value $m_axis HAS_TLAST 1

set_bus_parameter_value $clk_bus ASSOCIATED_BUSIF {s_axis:m_axis}
set_bus_parameter_value $clk_bus ASSOCIATED_RESET reset_n
set_bus_parameter_value $reset_bus POLARITY ACTIVE_LOW

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

set integrity [ipx::check_integrity -quiet $core]

puts ""
puts "============================================================"
puts "BUFFERED-HANDOFF TWO-TOWER IP PACKAGING COMPLETE"
puts "============================================================"
puts "IP root:       [file normalize $ip_root]"
puts "VLNV:          user.org:user:db2r:1.0"
puts "Integrity:     $integrity"
puts "Core cycles:   631810 per product"
puts "Handoff:       1025 clocks per nonfinal product"
puts "Core RAMB36:   72"
puts "============================================================"
puts ""

close_project
