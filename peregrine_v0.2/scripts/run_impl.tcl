# run_impl.tcl - Run Implementation
set project_dir "G:/mypro/Modena/peregrine_v0.2/vivado_proj"
open_project "$project_dir/peregrine_fpga.xpr"

launch_runs impl_1 -jobs [exec nproc]
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "Implementation completed successfully."
close_project
