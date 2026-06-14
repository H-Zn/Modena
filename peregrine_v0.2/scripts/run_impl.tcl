# run_impl.tcl - Run Implementation
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set vivado_proj "$project_dir/vivado_proj"

open_project "$vivado_proj/peregrine_fpga.xpr"

launch_runs impl_1 -jobs [exec nproc]
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "Implementation completed successfully."
close_project
