# run_synth_impl.tcl
# Run synthesis, implementation, and bitstream generation

# Open project (assumes it was created with create_project.tcl)
set project_dir "G:/mypro/Modena/peregrine_v0.2/vivado_proj"
open_project "$project_dir/peregrine_fpga.xpr"

# ============================================================================
# Synthesis
# ============================================================================
puts "Starting synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed!"
    open_run synth_1
    return
}
puts "Synthesis completed successfully."

# ============================================================================
# Implementation
# ============================================================================
puts "Starting implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    puts "ERROR: Implementation failed!"
    open_run impl_1
    return
}
puts "Implementation completed successfully."

# ============================================================================
# Generate Bitstream
# ============================================================================
puts "Bitstream generated: $project_dir/peregrine_fpga.runs/impl_1/peregrine_top.bit"

# Open implemented design
open_run impl_1

# Report timing summary
report_timing_summary -file "$project_dir/timing_summary.rpt"
puts "Timing report saved to: $project_dir/timing_summary.rpt"

# Report utilization
report_utilization -file "$project_dir/utilization.rpt"
puts "Utilization report saved to: $project_dir/utilization.rpt"

puts "Build completed successfully!"
close_project
