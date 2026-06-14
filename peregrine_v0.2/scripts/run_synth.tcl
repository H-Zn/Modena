# run_synth.tcl - Run Synthesis
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set vivado_proj "$project_dir/vivado_proj"

open_project "$vivado_proj/peregrine_fpga.xpr"

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
