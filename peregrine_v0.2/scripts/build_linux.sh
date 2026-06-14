#!/bin/bash
# ============================================================================
# Peregrine CPU - Linux Vivado Build Script
# Usage: chmod +x build_linux.sh && ./build_linux.sh
# ============================================================================

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PROJ="$PROJECT_DIR/vivado_proj"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Peregrine CPU FPGA Build Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查 Vivado
if ! command -v vivado &> /dev/null; then
    echo -e "${YELLOW}Vivado not found in PATH. Trying to source settings...${NC}"
    for settings in \
        "/opt/Xilinx/Vivado/2023.2/settings64.sh" \
        "/tools/Xilinx/Vivado/2023.2/settings64.sh" \
        "$HOME/Xilinx/Vivado/2023.2/settings64.sh"; do
        if [ -f "$settings" ]; then
            source "$settings"
            break
        fi
    done
    
    if ! command -v vivado &> /dev/null; then
        echo -e "${RED}ERROR: Vivado not found. Please install Vivado or source settings64.sh${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}[1/3] Creating Vivado project...${NC}"
cd "$SCRIPT_DIR"
vivado -mode batch -source create_project.tcl

echo -e "${GREEN}[2/3] Running synthesis and implementation...${NC}"
vivado -mode batch -source run_synth_impl.tcl

echo -e "${GREEN}[3/3] Build complete!${NC}"
echo ""
echo -e "${GREEN}Bitstream: $VIVADO_PROJ/peregrine_fpga.runs/impl_1/peregrine_top.bit${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Connect FPGA board via USB-JTAG"
echo "  2. Program: vivado -mode tcl -source $SCRIPT_DIR/program.tcl"
echo "  3. Open Tera Term, connect to COM port, baud rate 115200"
echo "  4. Power on the board - you should see 'Hello' repeated"
