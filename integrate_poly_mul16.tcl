set source_project "F:/repos/pynq_led/pynq_led.xpr"

set clone_name    "pynq_poly_mul16"
set clone_dir     "F:/repos/pynq_poly_mul16"
set clone_project [file join $clone_dir "${clone_name}.xpr"]

set ip_repo       "F:/repos/pynq_butterfly/ip/poly_mul16_1_0"
set deploy_dir    "F:/repos/pynq_butterfly/deploy"

set poly_vlnv     "user.org:user:poly_mul16:1.0"
set poly_instance "poly_mul16_0"

set poly_offset   0x43C20000
set poly_range    0x00010000

proc require_one {objects description} {
    if {[llength $objects] != 1} {
        error "Expected one $description; found [llength $objects]: $objects"
    }

    return [lindex $objects 0]
}

proc find_files_recursive {root pattern} {
    set matches {}

    foreach item [glob -nocomplain -directory $root *] {
        if {[file isdirectory $item]} {
            set matches [
                concat \
                    $matches \
                    [find_files_recursive $item $pattern]
            ]
        } elseif {[string match $pattern [file tail $item]]} {
            lappend matches $item
        }
    }

    return $matches
}

if {![file exists $source_project]} {
    error "Source project not found: $source_project"
}

if {![file exists [file join $ip_repo component.xml]]} {
    error "Packaged IP not found: $ip_repo"
}

puts ""
puts "============================================================"
puts "CREATING ISOLATED PROJECT CLONE"
puts "============================================================"

file delete -force $clone_dir

open_project $source_project

save_project_as \
    -force \
    $clone_name \
    $clone_dir

close_project

if {![file exists $clone_project]} {
    error "Cloned project was not created: $clone_project"
}

open_project $clone_project

puts "Clone: [get_property DIRECTORY [current_project]]"
puts "Part:  [get_property PART [current_project]]"
puts "Board: [get_property BOARD_PART [current_project]]"

puts ""
puts "============================================================"
puts "REGISTERING POLY_MUL16 IP"
puts "============================================================"

set existing_repos [
    get_property \
        ip_repo_paths \
        [current_project]
]

if {[lsearch -exact $existing_repos $ip_repo] < 0} {
    set_property \
        ip_repo_paths \
        [concat $existing_repos [list $ip_repo]] \
        [current_project]
}

update_ip_catalog

set poly_definition [
    require_one \
        [get_ipdefs -all -quiet $poly_vlnv] \
        "poly_mul16 IP definition"
]

puts "Using IP definition: $poly_definition"

set bd_file [
    require_one \
        [get_files -quiet *.bd] \
        "block-design file"
]

open_bd_design $bd_file

set bd_name [current_bd_design]

puts "Block design: $bd_name"

set interconnect [
    require_one \
        [get_bd_cells -quiet ps7_0_axi_periph] \
        "ps7_0_axi_periph cell"
]

set processing_system [
    require_one \
        [get_bd_cells -quiet processing_system7_0] \
        "processing_system7_0 cell"
]

set reset_block [
    require_one \
        [get_bd_cells -quiet rst_ps7_0_100M] \
        "rst_ps7_0_100M cell"
]

puts ""
puts "============================================================"
puts "ADDING THIRD AXI MASTER PORT"
puts "============================================================"

set_property \
    CONFIG.NUM_MI \
    {3} \
    $interconnect

set m02_axi [
    require_one \
        [get_bd_intf_pins -quiet ps7_0_axi_periph/M02_AXI] \
        "M02_AXI interface"
]

set m02_aclk [
    require_one \
        [get_bd_pins -quiet ps7_0_axi_periph/M02_ACLK] \
        "M02_ACLK pin"
]

set m02_aresetn [
    require_one \
        [get_bd_pins -quiet ps7_0_axi_periph/M02_ARESETN] \
        "M02_ARESETN pin"
]

puts ""
puts "============================================================"
puts "INSTANTIATING POLYNOMIAL MULTIPLIER"
puts "============================================================"

if {[llength [get_bd_cells -quiet $poly_instance]] != 0} {
    error "Cell already exists unexpectedly: $poly_instance"
}

create_bd_cell \
    -type ip \
    -vlnv $poly_vlnv \
    $poly_instance

set poly_axi [
    require_one \
        [get_bd_intf_pins -quiet ${poly_instance}/S_AXI] \
        "poly_mul16 S_AXI interface"
]

set poly_aclk [
    require_one \
        [get_bd_pins -quiet ${poly_instance}/S_AXI_ACLK] \
        "poly_mul16 clock pin"
]

set poly_aresetn [
    require_one \
        [get_bd_pins -quiet ${poly_instance}/S_AXI_ARESETN] \
        "poly_mul16 reset pin"
]

connect_bd_intf_net \
    $m02_axi \
    $poly_axi

set fabric_clock [
    require_one \
        [get_bd_pins -quiet processing_system7_0/FCLK_CLK0] \
        "FCLK_CLK0 pin"
]

set peripheral_resetn [
    require_one \
        [get_bd_pins -quiet rst_ps7_0_100M/peripheral_aresetn] \
        "peripheral_aresetn pin"
]

connect_bd_net \
    $fabric_clock \
    $m02_aclk \
    $poly_aclk

connect_bd_net \
    $peripheral_resetn \
    $m02_aresetn \
    $poly_aresetn

puts ""
puts "============================================================"
puts "ASSIGNING ADDRESS"
puts "============================================================"

set ps_data_space [
    require_one \
        [get_bd_addr_spaces -quiet processing_system7_0/Data] \
        "processing-system data address space"
]

set poly_slave_segments [
    get_bd_addr_segs \
        -quiet \
        -of_objects $poly_axi
]

if {[llength $poly_slave_segments] == 0} {
    set poly_slave_segments [
        get_bd_addr_segs \
            -quiet \
            ${poly_instance}/S_AXI/*
    ]
}

set poly_slave_segment [
    require_one \
        $poly_slave_segments \
        "poly_mul16 slave address segment"
]

create_bd_addr_seg \
    -range $poly_range \
    -offset $poly_offset \
    $ps_data_space \
    $poly_slave_segment \
    SEG_poly_mul16_0_S_AXI_registers

set assigned_segment [
    require_one \
        [get_bd_addr_segs \
            -quiet \
            processing_system7_0/Data/SEG_poly_mul16_0_S_AXI_registers] \
        "assigned poly_mul16 address segment"
]

puts "poly_mul16 offset: [get_property OFFSET $assigned_segment]"
puts "poly_mul16 range:  [get_property RANGE $assigned_segment]"

puts ""
puts "============================================================"
puts "VALIDATING BLOCK DESIGN"
puts "============================================================"

validate_bd_design
save_bd_design

generate_target \
    all \
    $bd_file

set wrapper_files [
    get_files \
        -quiet \
        *${bd_name}_wrapper.v
]

if {[llength $wrapper_files] == 0} {
    set wrapper_path [
        make_wrapper \
            -files $bd_file \
            -top
    ]

    add_files \
        -norecurse \
        $wrapper_path
}

update_compile_order \
    -fileset sources_1

save_project

puts ""
puts "============================================================"
puts "FINAL ADDRESS MAP"
puts "============================================================"

foreach segment [
    lsort [
        get_bd_addr_segs \
            -quiet \
            processing_system7_0/Data/*
    ]
] {
    puts [
        format \
            "%-75s offset=%-12s range=%s" \
            $segment \
            [get_property OFFSET $segment] \
            [get_property RANGE $segment]
    ]
}

puts ""
puts "============================================================"
puts "BUILDING BITSTREAM"
puts "============================================================"

reset_run synth_1
reset_run impl_1

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
    error "Synthesis did not complete successfully: $synth_status"
}

launch_runs \
    impl_1 \
    -to_step write_bitstream \
    -jobs 8

wait_on_run impl_1

set implementation_status [
    get_property \
        STATUS \
        [get_runs impl_1]
]

puts "Implementation status: $implementation_status"

if {![string match "*Complete*" $implementation_status]} {
    error "Implementation did not complete successfully: $implementation_status"
}

puts ""
puts "============================================================"
puts "COLLECTING PYNQ ARTIFACTS"
puts "============================================================"

file mkdir $deploy_dir

set top_name [
    get_property \
        TOP \
        [get_filesets sources_1]
]

set bit_path [
    file join \
        $clone_dir \
        "${clone_name}.runs" \
        impl_1 \
        "${top_name}.bit"
]

if {![file exists $bit_path]} {
    set bit_candidates [
        find_files_recursive \
            $clone_dir \
            "*.bit"
    ]

    set implementation_bits {}

    foreach candidate $bit_candidates {
        if {[string match "*impl_1*" $candidate]} {
            lappend implementation_bits $candidate
        }
    }

    set bit_path [
        require_one \
            $implementation_bits \
            "implementation bitstream"
    ]
}

set expected_hwh [
    file join \
        $clone_dir \
        "${clone_name}.gen" \
        sources_1 \
        bd \
        $bd_name \
        hw_handoff \
        "${bd_name}.hwh"
]

set hwh_path $expected_hwh

if {![file exists $hwh_path]} {
    set hwh_candidates [
        find_files_recursive \
            $clone_dir \
            "${bd_name}.hwh"
    ]

    set hwh_path [
        require_one \
            $hwh_candidates \
            "hardware handoff file"
    ]
}

set deploy_bit [
    file join \
        $deploy_dir \
        pynq_poly_mul16.bit
]

set deploy_hwh [
    file join \
        $deploy_dir \
        pynq_poly_mul16.hwh
]

file copy \
    -force \
    $bit_path \
    $deploy_bit

file copy \
    -force \
    $hwh_path \
    $deploy_hwh

set manifest_path [
    file join \
        $deploy_dir \
        pynq_poly_mul16.txt
]

set manifest [
    open \
        $manifest_path \
        w
]

puts $manifest "project=$clone_project"
puts $manifest "block_design=$bd_name"
puts $manifest "top=$top_name"
puts $manifest "ip=$poly_vlnv"
puts $manifest "poly_mul16_base=0x43C20000"
puts $manifest "poly_mul16_range=0x00010000"
puts $manifest "modadd_base=0x43C00000"
puts $manifest "modmul_base=0x43C10000"
puts $manifest "bitstream=$deploy_bit"
puts $manifest "hwh=$deploy_hwh"

close $manifest

puts ""
puts "============================================================"
puts "BUILD COMPLETE"
puts "============================================================"
puts "Project:   $clone_project"
puts "Bitstream: $deploy_bit"
puts "HWH:       $deploy_hwh"
puts "Manifest:  $manifest_path"
puts "poly_mul16 base: 0x43C20000"
puts "============================================================"
puts ""

close_project
