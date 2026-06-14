# build.bat
# Quick build script for Windows
# Usage: build.bat

@echo off
set VIVADO_PATH=C:/Xilinx/Vivado/2023.2/bin/vivado.bat
set PROJECT_DIR=G:/mypro/Modena/peregrine_v0.2/vivado_proj
set SCRIPT_DIR=G:/mypro/Modena/peregrine_v0.2/scripts

echo ====================================
echo Peregrine CPU FPGA Build
echo ====================================

echo.
echo [1/3] Creating Vivado project...
%VIVADO_PATH% -mode batch -source %SCRIPT_DIR%/create_project.tcl

echo.
echo [2/3] Running synthesis and implementation...
%VIVADO_PATH% -mode batch -source %SCRIPT_DIR%/run_synth_impl.tcl

echo.
echo [3/3] Build complete!
echo Reports: %PROJECT_DIR%/timing_summary.rpt
echo          %PROJECT_DIR%/utilization.rpt
echo Bitstream: %PROJECT_DIR%/peregrine_fpga.runs/impl_1/peregrine_top.bit

pause
