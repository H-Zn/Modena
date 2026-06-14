#!/bin/bash
# ============================================================================
# Peregrine CPU - Linux Vivado Build Script
# Usage: chmod +x build_linux.sh && ./build_linux.sh
# ============================================================================

set -e

# 配置
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VIVADO_PROJ="$PROJECT_DIR/vivado_proj"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
RTL_DIR="$PROJECT_DIR/rtl"
CONSTRAINTS_DIR="$PROJECT_DIR/constraints"

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
    if [ -f "/opt/Xilinx/Vivado/2023.2/settings64.sh" ]; then
        source /opt/Xilinx/Vivado/2023.2/settings64.sh
    elif [ -f "/tools/Xilinx/Vivado/2023.2/settings64.sh" ]; then
        source /tools/Xilinx/Vivado/2023.2/settings64.sh
    else
        echo -e "${RED}ERROR: Vivado not found. Please install Vivado or source settings64.sh${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}[1/5] Creating Vivado project...${NC}"
vivado -mode batch -source "$SCRIPTS_DIR/create_project.tcl" -log "$VIVADO_PROJ/create_project.log"

echo -e "${GREEN}[2/5] Running synthesis...${NC}"
vivado -mode batch -source "$SCRIPTS_DIR/run_synth.tcl" -log "$VIVADO_PROJ/synth.log"

echo -e "${GREEN}[3/5] Running implementation...${NC}"
vivado -mode batch -source "$SCRIPTS_DIR/run_impl.tcl" -log "$VIVADO_PROJ/impl.log"

echo -e "${GREEN}[4/5] Generating bitstream...${NC}"
vivado -mode batch -source "$SCRIPTS_DIR/gen_bitstream.tcl" -log "$VIVADO_PROJ/bitstream.log"

echo -e "${GREEN}[5/5] Build complete!${NC}"
echo ""
echo -e "${GREEN}Bitstream: $VIVADO_PROJ/peregrine_fpga.runs/impl_1/peregrine_top.bit${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Connect FPGA board via USB-JTAG"
echo "  2. Open Hardware Manager: vivado -mode tcl -source $SCRIPTS_DIR/program.tcl"
echo "  3. Open Tera Term, connect to COM port, baud rate 115200"
echo "  4. Power on the board - you should see 'Hello' repeated"
