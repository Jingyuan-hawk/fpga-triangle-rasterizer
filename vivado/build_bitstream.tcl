set project_root [file normalize [file join [file dirname [info script]] ..]]
set project_path [file join $project_root build vivado_100 arty_rasterizer_100.xpr]
if {![file exists $project_path]} {
    error "Project not found; run create_project.tcl first: $project_path"
}
open_project $project_path
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set status [get_property STATUS [get_runs impl_1]]
puts "IMPLEMENTATION_STATUS=$status"
if {[string first "Complete" $status] < 0} {
    error "Implementation did not complete: $status"
}
open_run impl_1
report_timing_summary -file [file join $project_root build arty_post_route_timing.rpt]
report_utilization -file [file join $project_root build arty_post_route_utilization.rpt]
set worst_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst_path] == 0} {
    error "No setup timing path was found"
}
set setup_slack [get_property SLACK $worst_path]
puts "SETUP_WNS_NS=$setup_slack"
if {$setup_slack < 0} {
    error "100 MHz setup timing is not met; bitstream was not published"
}
set bit_file [file join $project_root build vivado_100 arty_rasterizer_100.runs impl_1 arty_a7_top.bit]
if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file"
}
file copy -force $bit_file [file join $project_root arty_a7_rasterizer.bit]
puts "BITSTREAM=[file join $project_root arty_a7_rasterizer.bit]"
