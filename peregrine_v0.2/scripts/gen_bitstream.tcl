# gen_bitstream.tcl - Generate Bitstream
set project_dir "G:/mypro/Modena/peregrine_v0.2/vivado_proj"
open_project "$project_dir/peregrine_fpga.xpr"

launch_runs impl_1 -to_step write_bitstream -jobs [exec nproc]
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    puts "ERROR: Bitstream generation failed!"
    exit 1
}
puts "Bitstream generated successfully."
puts "Location: $project_dir/peregrine_fpga.runs/impl_1/peregrine_top.bit"
close_project
