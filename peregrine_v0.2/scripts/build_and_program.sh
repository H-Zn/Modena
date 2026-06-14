#!/bin/bash
# ============================================================================
# 快速构建脚本 (仅综合+烧录，不看串口)
# Usage: ./build_and_program.sh
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PROJ="$PROJECT_DIR/vivado_proj"

# 检查 Vivado
if ! command -v vivado &> /dev/null; then
    for f in /opt/Xilinx/Vivado/*/settings64.sh \
             /tools/Xilinx/Vivado/*/settings64.sh \
             $HOME/Xilinx/Vivado/*/settings64.sh; do
        [ -f "$f" ] && source "$f" && break
    done
fi

echo "========================================"
echo "   Peregrine FPGA Build & Program"
echo "========================================"

# 构建
echo "[1/2] Building..."
vivado -mode batch -source "$SCRIPT_DIR/create_project.tcl" -nojournal -nolog
vivado -mode batch -source "$SCRIPT_DIR/run_synth_impl.tcl" -nojournal -nolog

# 烧录
echo "[2/2] Programming..."
vivado -mode batch -source "$SCRIPT_DIR/program.tcl" -nojournal -nolog

echo "========================================"
echo "Done! FPGA is running."
echo "Connect serial (115200 8N1) to see output."
echo "========================================"
