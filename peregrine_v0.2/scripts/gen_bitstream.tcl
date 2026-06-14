# gen_bitstream.tcl - Generate Bitstream
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set vivado_proj "$project_dir/vivado_proj"

open_project "$vivado_proj/peregrine_fpga.xpr"

launch_runs impl_1 -to_step write_bitstream -jobs [exec nproc]
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    puts "ERROR: Bitstream generation failed!"
    exit 1
}
puts "Bitstream generated successfully."
puts "Location: $vivado_proj/peregrine_fpga.runs/impl_1/peregrine_top.bit"
close_project
