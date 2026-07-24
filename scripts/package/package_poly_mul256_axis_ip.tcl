set root_dir [file dirname [file dirname [file dirname [file normalize [info script]]]]]
set rtl_dir  [file join $root_dir rtl]
set mem_dir  [file join $root_dir model golden_n256]

set work_dir [
    file join \
        $root_dir \
        vivado \
        package_poly_mul256_axis
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
        poly_mul256_axis_1_0
]

set report_dir [
    file join \
        $root_dir \
        reports \
        poly_mul256_axis
]

set constraint_file [
    file join \
        $work_dir \
        poly_mul256_axis_clock.xdc
]

proc require_file {path} {
    if {![file exists $path]} {
        error "Required file does not exist: $path"
    }
}

proc require_one {objects description} {
    if {[llength $objects] != 1} {
        error "Expected one $description; found [llength $objects]: $objects"
    }

    return [lindex $objects 0]
}

proc map_interface_port {
    interface logical_name physical_name
} {
    set port_map [
        ipx::add_port_map \
            $logical_name \
            $interface
    ]

    set_property \
        physical_name \
        $physical_name \
        $port_map
}

puts ""
puts "============================================================"
puts "POLY_MUL256 AXI-STREAM PACKAGE"
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
    package_poly_mul256_axis \
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
    [file join $rtl_dir poly_mul256_axis_core.sv] \
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
    poly_mul256_axis_core \
    [get_filesets sources_1]

set constraint_handle [
    open \
        $constraint_file \
        w
]

puts $constraint_handle {
create_clock -name aclk -period 10.000 [get_ports aclk]
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

set_property vendor        user.org        $core
set_property library       user            $core
set_property name          poly_mul256_axis $core
set_property version       1.0             $core
set_property core_revision 1               $core

set_property \
    display_name \
    {OpenFHE N=256 AXI-Stream Polynomial Multiplier} \
    $core

set_property \
    description \
    {DMA-ready AXI4-Stream adapter for the constant-time BRAM-backed OpenFHE-profile N=256 negacyclic polynomial multiplier.} \
    $core

# Remove automatically inferred interfaces so the exact AXI-Stream
# interface maps below are authoritative.
foreach interface [
    ipx::get_bus_interfaces \
        -of_objects $core
] {
    ipx::remove_bus_interface \
        [get_property NAME $interface] \
        $core
}

puts "Creating S_AXIS interface..."

set s_axis [
    ipx::add_bus_interface \
        S_AXIS \
        $core
]

set_property \
    bus_type_vlnv \
    xilinx.com:interface:axis:1.0 \
    $s_axis

set_property \
    abstraction_type_vlnv \
    xilinx.com:interface:axis_rtl:1.0 \
    $s_axis

set_property \
    interface_mode \
    slave \
    $s_axis

map_interface_port \
    $s_axis \
    TDATA \
    s_axis_tdata

map_interface_port \
    $s_axis \
    TKEEP \
    s_axis_tkeep

map_interface_port \
    $s_axis \
    TVALID \
    s_axis_tvalid

map_interface_port \
    $s_axis \
    TREADY \
    s_axis_tready

map_interface_port \
    $s_axis \
    TLAST \
    s_axis_tlast

puts "Creating M_AXIS interface..."

set m_axis [
    ipx::add_bus_interface \
        M_AXIS \
        $core
]

set_property \
    bus_type_vlnv \
    xilinx.com:interface:axis:1.0 \
    $m_axis

set_property \
    abstraction_type_vlnv \
    xilinx.com:interface:axis_rtl:1.0 \
    $m_axis

set_property \
    interface_mode \
    master \
    $m_axis

map_interface_port \
    $m_axis \
    TDATA \
    m_axis_tdata

map_interface_port \
    $m_axis \
    TKEEP \
    m_axis_tkeep

map_interface_port \
    $m_axis \
    TVALID \
    m_axis_tvalid

map_interface_port \
    $m_axis \
    TREADY \
    m_axis_tready

map_interface_port \
    $m_axis \
    TLAST \
    m_axis_tlast

puts "Creating clock interface..."

set clock_interface [
    ipx::add_bus_interface \
        ACLK \
        $core
]

set_property \
    bus_type_vlnv \
    xilinx.com:signal:clock:1.0 \
    $clock_interface

set_property \
    abstraction_type_vlnv \
    xilinx.com:signal:clock_rtl:1.0 \
    $clock_interface

set_property \
    interface_mode \
    slave \
    $clock_interface

map_interface_port \
    $clock_interface \
    CLK \
    aclk

set associated_busif [
    ipx::add_bus_parameter \
        ASSOCIATED_BUSIF \
        $clock_interface
]

set_property \
    value \
    {S_AXIS:M_AXIS} \
    $associated_busif

set associated_reset [
    ipx::add_bus_parameter \
        ASSOCIATED_RESET \
        $clock_interface
]

set_property \
    value \
    ARESETN \
    $associated_reset

set clock_frequency [
    ipx::add_bus_parameter \
        FREQ_HZ \
        $clock_interface
]

set_property \
    value \
    100000000 \
    $clock_frequency

puts "Creating reset interface..."

set reset_interface [
    ipx::add_bus_interface \
        ARESETN \
        $core
]

set_property \
    bus_type_vlnv \
    xilinx.com:signal:reset:1.0 \
    $reset_interface

set_property \
    abstraction_type_vlnv \
    xilinx.com:signal:reset_rtl:1.0 \
    $reset_interface

set_property \
    interface_mode \
    slave \
    $reset_interface

map_interface_port \
    $reset_interface \
    RST \
    aresetn

set reset_polarity [
    ipx::add_bus_parameter \
        POLARITY \
        $reset_interface
]

set_property \
    value \
    ACTIVE_LOW \
    $reset_polarity

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

set synthesis_status [
    get_property \
        STATUS \
        [get_runs synth_1]
]

puts "Synthesis status: $synthesis_status"

if {![string match "*Complete*" $synthesis_status]} {
    error "Synthesis failed: $synthesis_status"
}

open_run synth_1

set utilization_report [
    file join \
        $report_dir \
        poly_mul256_axis_utilization.rpt
]

set timing_report [
    file join \
        $report_dir \
        poly_mul256_axis_timing.rpt
]

report_utilization \
    -file $utilization_report

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
puts "AXI-STREAM PACKAGE COMPLETE"
puts "============================================================"
puts "VLNV: user.org:user:poly_mul256_axis:1.0"
puts "IP directory: $ip_dir"
puts "Component: [file join $ip_dir component.xml]"
puts "Synthesis: $synthesis_status"
puts "RAMB18E1 cells: $ramb18_count"
puts "RAMB36E1 cells: $ramb36_count"
puts "DSP48E1 cells:  $dsp_count"
puts "Utilization: $utilization_report"
puts "Timing: $timing_report"
puts "============================================================"
puts ""

close_project
