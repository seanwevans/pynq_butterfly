set project_path "F:/repos/pynq_led/pynq_led.xpr"
set ip_repo      "F:/repos/pynq_butterfly/ip/poly_mul16_1_0"
set report_path  "F:/repos/pynq_butterfly/artifacts/deploy/pynq_led/inventory.txt"

proc emit {handle text} {
    puts $text
    puts $handle $text
}

if {![file exists $project_path]} {
    error "Project not found: $project_path"
}

if {![file exists [file join $ip_repo component.xml]]} {
    error "Packaged IP not found: $ip_repo"
}

open_project $project_path

set existing_repos [get_property ip_repo_paths [current_project]]

if {[lsearch -exact $existing_repos $ip_repo] < 0} {
    set_property \
        ip_repo_paths \
        [concat $existing_repos [list $ip_repo]] \
        [current_project]
}

update_ip_catalog

set packaged_defs [
    get_ipdefs \
        -all \
        -quiet \
        "user.org:user:poly_mul16:*"
]

if {[llength $packaged_defs] == 0} {
    error "poly_mul16 was not found in the updated IP catalog"
}

file mkdir [file dirname $report_path]
set handle [open $report_path w]

emit $handle "============================================================"
emit $handle "PROJECT"
emit $handle "============================================================"
emit $handle "name=[get_property NAME [current_project]]"
emit $handle "part=[get_property PART [current_project]]"
emit $handle "board_part=[get_property BOARD_PART [current_project]]"
emit $handle "directory=[get_property DIRECTORY [current_project]]"

emit $handle ""
emit $handle "============================================================"
emit $handle "IP REPOSITORIES"
emit $handle "============================================================"

foreach repo [get_property ip_repo_paths [current_project]] {
    emit $handle $repo
}

emit $handle ""
emit $handle "============================================================"
emit $handle "POLY_MUL16 IP DEFINITIONS"
emit $handle "============================================================"

foreach definition $packaged_defs {
    emit $handle $definition
}

set bd_files [get_files -quiet *.bd]

if {[llength $bd_files] == 0} {
    close $handle
    error "No block-design files were found"
}

foreach bd_file $bd_files {
    open_bd_design $bd_file

    emit $handle ""
    emit $handle "============================================================"
    emit $handle "BLOCK DESIGN: [current_bd_design]"
    emit $handle "FILE: $bd_file"
    emit $handle "============================================================"

    emit $handle ""
    emit $handle "CELLS"

    foreach cell [lsort [get_bd_cells -quiet]] {
        set vlnv [get_property VLNV $cell]

        if {$vlnv eq ""} {
            set vlnv "<hierarchical>"
        }

        emit $handle [format "%-40s %s" $cell $vlnv]
    }

    emit $handle ""
    emit $handle "INTERFACE PINS"

    foreach pin [lsort [get_bd_intf_pins -quiet -hierarchical]] {
        set mode [get_property MODE $pin]
        set vlnv ""

        catch {
            set vlnv [get_property VLNV $pin]
        }

        emit $handle [format "%-60s mode=%-8s vlnv=%s" $pin $mode $vlnv]
    }

    emit $handle ""
    emit $handle "ADDRESS SPACES"

    foreach space [lsort [get_bd_addr_spaces -quiet]] {
        emit $handle $space
    }

    emit $handle ""
    emit $handle "ADDRESS SEGMENTS"

    foreach segment [lsort [get_bd_addr_segs -quiet]] {
        set offset "<unset>"
        set range  "<unset>"

        catch {
            set offset [get_property OFFSET $segment]
        }

        catch {
            set range [get_property RANGE $segment]
        }

        emit $handle [format "%-70s offset=%-12s range=%s" \
            $segment \
            $offset \
            $range]
    }

    validate_bd_design
}

close $handle
close_project

puts ""
puts "============================================================"
puts "PROJECT INVENTORY COMPLETE"
puts "Report: $report_path"
puts "============================================================"
