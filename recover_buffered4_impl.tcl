set_param general.maxThreads 1

set project_root F:/v/p4ttbo_dma
set run_dir [file join $project_root p4ttbo_dma.runs impl_1]

set candidates \
    [glob -nocomplain [file join $run_dir *_placed.dcp]]

if {[llength $candidates] != 1} {
    error "Expected one placed checkpoint, found: $candidates"
}

set placed_checkpoint [lindex $candidates 0]

set report_dir \
    F:/repos/pynq_butterfly/reports/poly_mul4096_four_butterfly_two_tower_buffered_dma/recovery_single_thread

file delete -force $report_dir
file mkdir $report_dir

puts ""
puts "Placed checkpoint: $placed_checkpoint"
puts ""

open_checkpoint $placed_checkpoint

puts ""
puts "Routing directly from placed checkpoint..."
puts ""

route_design \
    -directive NoTimingRelaxation \
    -tns_cleanup

set routed_path \
    [lindex \
        [get_timing_paths \
            -quiet \
            -delay_type max \
            -max_paths 1] \
        0]

set routed_wns \
    [get_property SLACK $routed_path]

puts ""
puts "Routed WNS: $routed_wns ns"
puts ""

if {$routed_wns < 0.0} {
    puts "Running single-threaded post-route physical optimization..."

    phys_opt_design \
        -directive Explore
}

set final_path \
    [lindex \
        [get_timing_paths \
            -quiet \
            -delay_type max \
            -max_paths 1] \
        0]

set final_wns \
    [get_property SLACK $final_path]

set datapath_ns \
    [get_property DATAPATH_DELAY $final_path]

set logic_levels \
    [get_property LOGIC_LEVELS $final_path]

set startpoint \
    [get_property STARTPOINT_PIN $final_path]

set endpoint \
    [get_property ENDPOINT_PIN $final_path]

report_timing_summary \
    -delay_type max \
    -max_paths 100 \
    -file [file join $report_dir timing_summary.rpt]

report_utilization \
    -file [file join $report_dir utilization.rpt]

write_checkpoint \
    -force \
    [file join $report_dir routed.dcp]

puts ""
puts "============================================================"
puts "BUFFERED4 RECOVERY RESULT"
puts "============================================================"
puts "Routed WNS:  $routed_wns ns"
puts "Final WNS:   $final_wns ns"
puts "Datapath:    $datapath_ns ns"
puts "Levels:      $logic_levels"
puts "Startpoint:  $startpoint"
puts "Endpoint:    $endpoint"
puts "============================================================"
puts ""

if {$final_wns < 0.0} {
    error "Recovered design still fails timing: WNS=$final_wns ns"
}

set bitstream \
    [file join $run_dir d_wrapper.bit]

write_bitstream \
    -force \
    $bitstream

puts "Bitstream: $bitstream"
