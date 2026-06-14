# program.tcl - Program FPGA via JTAG
# Usage: vivado -mode tcl -source program.tcl

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set vivado_proj "$project_dir/vivado_proj"
set bitstream "$vivado_proj/peregrine_fpga.runs/impl_1/peregrine_top.bit"

# 打开 Hardware Manager
open_hw_manager

# 连接服务器
connect_hw_server
puts "HW Server connected."

# 打开目标 (自动检测)
open_hw_target
puts "HW Target opened."

# 获取设备
set hw_device [lindex [get_hw_devices] 0]
puts "Found device: $hw_device"

# 设置 bitstream
set_property PROGRAM.FILE $bitstream $hw_device

# 烧录
program_hw_devices $hw_device
puts "Programming complete!"

# 断开
close_hw_target
disconnect_hw_server
close_hw_manager
puts "FPGA programmed successfully. Board should now run."
