# create_project.tcl
# Create Vivado project for Peregrine CPU

# Parameters
set project_name "peregrine_fpga"
set project_dir  "G:/mypro/Modena/peregrine_v0.2/vivado_proj"
set rtl_dir      "G:/mypro/Modena/peregrine_v0.2/rtl"
set constraints_dir "G:/mypro/Modena/peregrine_v0.2/constraints"
set part         "xc7a35tcpg236-1"

# Create project
create_project $project_name $project_dir -part $part -force

# Set project properties
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]
set_property simulator_language Verilog [current_project]

# Add RTL source files
set rtl_files [list \
    "$rtl_dir/include/cpu_pkg.sv" \
    "$rtl_dir/top/clk_rst_manager.sv" \
    "$rtl_dir/top/top.sv" \
    "$rtl_dir/uart_tx.sv" \
    "$rtl_dir/frontend/pc.sv" \
    "$rtl_dir/frontend/perceptron_predictor.sv" \
    "$rtl_dir/frontend/btb.sv" \
    "$rtl_dir/frontend/ras.sv" \
    "$rtl_dir/frontend/branch_floder.sv" \
    "$rtl_dir/frontend/icache.sv" \
    "$rtl_dir/frontend/itcm.sv" \
    "$rtl_dir/frontend/inst_aligner.sv" \
    "$rtl_dir/decode/decoder.sv" \
    "$rtl_dir/decode/dep_checker.sv" \
    "$rtl_dir/decode/dae_spiltter.sv" \
    "$rtl_dir/execute/agu.sv" \
    "$rtl_dir/execute/alu_island.sv" \
    "$rtl_dir/execute/bru_island.sv" \
    "$rtl_dir/execute/mul_div_island.sv" \
    "$rtl_dir/execute/bypass_network.sv" \
    "$rtl_dir/execute/regfile.sv" \
    "$rtl_dir/execute/eiq.sv" \
    "$rtl_dir/execute/maq.sv" \
    "$rtl_dir/memory/dcache.sv" \
    "$rtl_dir/memory/mshr.sv" \
    "$rtl_dir/memory/tcm.sv" \
    "$rtl_dir/memory/axt_interface.sv" \
    "$rtl_dir/memory/stride_prefetcher.sv" \
    "$rtl_dir/commit/srb.sv" \
    "$rtl_dir/commit/store_buffer.sv" \
    "$rtl_dir/commit/writeback_sync.sv" \
    "$rtl_dir/control/flush_controller.sv" \
    "$rtl_dir/control/exception_handler.sv" \
    "$rtl_dir/control/pref_counter.sv" \
]

add_files -norecurse $rtl_files

# Set SystemVerilog as file type for .sv files
foreach f $rtl_files {
    set_property file_type SystemVerilog [get_files $f]
}

# Add constraints
add_files -fileset constrs_1 -norecurse "$constraints_dir/peregrine.xdc"

# Set top module
set_property top peregrine_top [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

puts "Project created successfully at: $project_dir"
