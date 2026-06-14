#!/bin/bash
# ============================================================================
# Peregrine CPU - Linux 全流程脚本 (综合+烧录+串口)
# Usage: ./run_all.sh
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PROJ="$PROJECT_DIR/vivado_proj"
BITSTREAM="$VIVADO_PROJ/peregrine_fpga.runs/impl_1/peregrine_top.bit"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Step 0: 检查 Vivado
# ============================================================================
if ! command -v vivado &> /dev/null; then
    echo -e "${YELLOW}Vivado not in PATH, sourcing settings...${NC}"
    for f in /opt/Xilinx/Vivado/*/settings64.sh \
             /tools/Xilinx/Vivado/*/settings64.sh \
             $HOME/Xilinx/Vivado/*/settings64.sh \
             $HOME/tools/Xilinx/Vivado/*/settings64.sh; do
        [ -f "$f" ] && source "$f" && break
    done
fi

if ! command -v vivado &> /dev/null; then
    echo -e "${RED}ERROR: Vivado not found${NC}"
    echo "Usage: source /opt/Xilinx/Vivado/<version>/settings64.sh"
    exit 1
fi
echo -e "${GREEN}[OK] Vivado found: $(vivado -version | head -1)${NC}"

# ============================================================================
# Step 1: 创建工程 + 综合 + 实现 + 生成Bitstream
# ============================================================================
echo ""
echo -e "${CYAN}========== Step 1: Build ==========${NC}"

# 检查是否已有bitstream，询问是否跳过
if [ -f "$BITSTREAM" ]; then
    echo -e "${YELLOW}Bitstream already exists: $BITSTREAM${NC}"
    read -p "跳过构建直接烧录? (y/N): " SKIP_BUILD
    if [ "$SKIP_BUILD" != "y" ] && [ "$SKIP_BUILD" != "Y" ]; then
        SKIP_BUILD="n"
    fi
else
    SKIP_BUILD="n"
fi

if [ "$SKIP_BUILD" != "y" ] && [ "$SKIP_BUILD" != "Y" ]; then
    echo -e "${GREEN}[1/4] Creating project...${NC}"
    vivado -mode batch -source "$SCRIPT_DIR/create_project.tcl" -nojournal -nolog

    echo -e "${GREEN}[2/4] Synthesis...${NC}"
    vivado -mode batch -source "$SCRIPT_DIR/run_synth.tcl" -nojournal -nolog

    echo -e "${GREEN}[3/4] Implementation...${NC}"
    vivado -mode batch -source "$SCRIPT_DIR/run_impl.tcl" -nojournal -nolog

    echo -e "${GREEN}[4/4] Bitstream...${NC}"
    vivado -mode batch -source "$SCRIPT_DIR/gen_bitstream.tcl" -nojournal -nolog

    if [ ! -f "$BITSTREAM" ]; then
        echo -e "${RED}ERROR: Bitstream generation failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}[OK] Bitstream ready: $BITSTREAM${NC}"

# ============================================================================
# Step 2: 烧录 FPGA
# ============================================================================
echo ""
echo -e "${CYAN}========== Step 2: Program FPGA ==========${NC}"
echo "请确保:"
echo "  1. FPGA开发板已通过USB-JTAG线连接"
echo "  2. 开发板已上电"
echo ""
read -p "按 Enter 继续烧录, Ctrl+C 取消... "

vivado -mode batch -source "$SCRIPT_DIR/program.tcl" -nojournal -nolog 2>&1 | grep -v "^$" || true

echo -e "${GREEN}[OK] FPGA programmed${NC}"

# ============================================================================
# Step 3: 检测串口
# ============================================================================
echo ""
echo -e "${CYAN}========== Step 3: Serial Port ==========${NC}"

# 自动检测串口
SERIAL_PORT=""
for p in /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyUSB1 /dev/ttyACM1 /dev/ttyS0; do
    if [ -e "$p" ]; then
        SERIAL_PORT="$p"
        break
    fi
done

if [ -z "$SERIAL_PORT" ]; then
    echo "未检测到串口设备。"
    echo "可用串口设备:"
    ls /dev/tty* 2>/dev/null | grep -E "(USB|ACM|S[0-9])" || echo "  (无)"
    echo ""
    read -p "请输入串口设备路径 (如 /dev/ttyUSB0): " SERIAL_PORT
fi

echo -e "${GREEN}[OK] Serial port: $SERIAL_PORT${NC}"

# ============================================================================
# Step 4: 读取串口
# ============================================================================
echo ""
echo -e "${CYAN}========== Step 4: Serial Monitor ==========${NC}"
echo "波特率: 115200, 8N1"
echo "按 Ctrl+A 然后 X 退出 minicom"
echo "或者按 Ctrl+C 退出脚本"
echo ""
echo "预期输出: Hello Hello Hello ..."
echo "========================================="
echo ""

# 按复位键后读取串口
sleep 1

if command -v minicom &> /dev/null; then
    sudo minicom -D "$SERIAL_PORT" -b 115200 -o
elif command -v picocom &> /dev/null; then
    sudo picocom -b 115200 "$SERIAL_PORT"
elif command -v screen &> /dev/null; then
    sudo screen "$SERIAL_PORT" 115200
else
    echo -e "${YELLOW}未找到串口工具，尝试用stty+cat...${NC}"
    echo "按 Ctrl+C 退出"
    echo ""
    sudo stty -F "$SERIAL_PORT" 115200 cs8 -cstopb -parenb
    sudo cat "$SERIAL_PORT"
fi
