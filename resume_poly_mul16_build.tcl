set project_path "F:/repos/pynq_poly_mul16/pynq_poly_mul16.xpr"
set ip_repo      "F:/repos/pynq_butterfly/ip/poly_mul16_1_0"
set deploy_dir   "F:/repos/pynq_butterfly/deploy"

set expected_base  0x43C20000
set expected_range 0x00010000

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

if {![file exists $project_path]} {
    error "Integrated project not found: $project_path"
}

if {![file exists [file join $ip_repo component.xml]]} {
    error "Packaged IP not found: $ip_repo"
}

puts ""
puts "============================================================"
puts "OPENING INTEGRATED PROJECT"
puts "============================================================"

open_project $project_path

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

set bd_file [
    require_one \
        [get_files -quiet *.bd] \
        "block-design file"
]

open_bd_design $bd_file

set bd_name [current_bd_design]

set poly_cell [
    require_one \
        [get_bd_cells -quiet poly_mul16_0] \
        "poly_mul16_0 cell"
]

set poly_segment [
    require_one \
        [get_bd_addr_segs \
            -quiet \
            processing_system7_0/Data/SEG_poly_mul16_0_S_AXI_registers] \
        "poly_mul16 address segment"
]

set actual_base [
    get_property \
        OFFSET \
        $poly_segment
]

set actual_range [
    get_property \
        RANGE \
        $poly_segment
]

puts "Project: [get_property NAME [current_project]]"
puts "Block design: $bd_name"
puts "Polynomial multiplier: [get_property VLNV $poly_cell]"
puts "Address: $actual_base"
puts "Range:   $actual_range"

if {$actual_base ne $expected_base} {
    error "Unexpected base address: $actual_base"
}

if {$actual_range ne $expected_range} {
    error "Unexpected address range: $actual_range"
}

puts ""
puts "============================================================"
puts "VALIDATING AND GENERATING BLOCK DESIGN"
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

set top_name [
    get_property \
        TOP \
        [get_filesets sources_1]
]

puts "Top module: $top_name"

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
puts "RUNNING SYNTHESIS"
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

puts ""
puts "============================================================"
puts "RUNNING IMPLEMENTATION AND BITSTREAM"
puts "============================================================"

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

set project_dir [
    get_property \
        DIRECTORY \
        [current_project]
]

set project_name [
    get_property \
        NAME \
        [current_project]
]

set expected_bit [
    file join \
        $project_dir \
        "${project_name}.runs" \
        impl_1 \
        "${top_name}.bit"
]

set bit_path $expected_bit

if {![file exists $bit_path]} {
    set bit_candidates [
        find_files_recursive \
            $project_dir \
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
        $project_dir \
        "${project_name}.gen" \
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
            $project_dir \
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

puts $manifest "project=$project_path"
puts $manifest "block_design=$bd_name"
puts $manifest "top=$top_name"
puts $manifest "poly_mul16_base=0x43C20000"
puts $manifest "poly_mul16_range=0x00010000"
puts $manifest "modadd_base=0x43C00000"
puts $manifest "modmul_base=0x43C10000"
puts $manifest "bitstream=$deploy_bit"
puts $manifest "hwh=$deploy_hwh"
puts $manifest "synthesis_status=$synth_status"
puts $manifest "implementation_status=$implementation_status"

close $manifest

puts ""
puts "============================================================"
puts "BUILD COMPLETE"
puts "============================================================"
puts "Project:   $project_path"
puts "Top:       $top_name"
puts "Bitstream: $deploy_bit"
puts "HWH:       $deploy_hwh"
puts "Manifest:  $manifest_path"
puts "poly_mul16 base: 0x43C20000"
puts "============================================================"
puts ""

close_project
