## ============================================================================
## Peregrine CPU - FPGA Pin Constraints
## 目标板: XC7A35A100
## ============================================================================

## ============================================================================
## 时钟 (50MHz, 如时钟不同请修改create_clock周期)
## ============================================================================
set_property PACKAGE_PIN J15 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000] [get_ports clk_i]
## 如果是100MHz: create_clock -period 10.000 ...

## ============================================================================
## 复位按钮
## ============================================================================
set_property PACKAGE_PIN L18 [get_ports rst_n_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n_i]

## ============================================================================
## UART (CH340 USB转串口)
## CH340 TX -> CPU RX; CH340 RX <- CPU TX
## ============================================================================
set_property PACKAGE_PIN V2 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property PACKAGE_PIN U2 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

## ============================================================================
## LED 调试
## ============================================================================
set_property PACKAGE_PIN K13 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN M18 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

## ============================================================================
## 时序约束
## ============================================================================
set_property ASYNCHRONOUS_REG TRUE [get_pins clk_rst_manager_inst/rst_sync_ff1_reg]
set_property ASYNCHRONOUS_REG TRUE [get_pins clk_rst_manager_inst/rst_sync_ff2_reg]
set_false_path -from [get_ports rst_n_i]
