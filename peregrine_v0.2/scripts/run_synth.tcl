# run_synth.tcl - Run Synthesis
set project_dir "G:/mypro/Modena/peregrine_v0.2/vivado_proj"
open_project "$project_dir/peregrine_fpga.xpr"

reset_run synth_1
launch_runs synth_1 -jobs [exec nproc]
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    open_run synth_1
    exit 1
}
puts "Synthesis completed successfully."
close_project
