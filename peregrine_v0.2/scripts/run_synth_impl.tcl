# run_synth_impl.tcl - Combined Synthesis and Implementation
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set vivado_proj "$project_dir/vivado_proj"

open_project "$vivado_proj/peregrine_fpga.xpr"

# Synthesis
puts "Starting synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs [exec nproc]
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    open_run synth_1
    exit 1
}
puts "Synthesis completed successfully."

# Implementation
puts "Starting implementation..."
launch_runs impl_1 -jobs [exec nproc]
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation failed!"
    exit 1
}
puts "Implementation completed successfully."

# Bitstream
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs [exec nproc]
wait_on_run impl_1

puts "All done! Bitstream: $vivado_proj/peregrine_fpga.runs/impl_1/peregrine_top.bit"
close_project
