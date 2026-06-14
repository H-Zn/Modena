#!/bin/bash
# ============================================================================
# Peregrine CPU - Linux 完整构建与测试脚本
# Usage: chmod +x build_and_test.sh && ./build_and_test.sh
# ============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "========================================"
echo "   Peregrine CPU FPGA Build & Test"
echo "========================================"
echo ""

# 1. 构建
echo "[1/6] Creating Vivado project..."
cd "$PROJECT_DIR/scripts"
bash build_linux.sh

# 2. 检查 bitstream
BITSTREAM="$PROJECT_DIR/vivado_proj/peregrine_fpga.runs/impl_1/peregrine_top.bit"
if [ ! -f "$BITSTREAM" ]; then
    echo "ERROR: Bitstream not found at $BITSTREAM"
    exit 1
fi
echo "[2/6] Bitstream generated: $BITSTREAM"

# 3. 烧录
echo "[3/6] Programming FPGA..."
cd "$PROJECT_DIR/scripts"
vivado -mode tcl -source program.tcl

# 4. 等待用户连接串口
echo ""
echo "[4/6] FPGA programmed!"
echo ""
echo "请按以下步骤操作:"
echo "  1. 用USB线连接开发板的USB-UART口"
echo "  2. 打开 Tera Term:"
echo "     文件 → 新建连接 → 串口 (COMx)"
echo "  3. 设置串口:"
echo "     波特率: 115200"
echo "     数据位: 8"
echo "     停止位: 1"
echo "     校验: 无"
echo "     流控: 无"
echo "  4. 按下开发板复位键"
echo ""
echo "[5/6] 按 Enter 继续测试, 或 Ctrl+C 退出..."
read -p ""

# 5. 测试串口
echo "[6/6] 测试串口输出..."
echo "========================================"
echo "  以下应该是 'Hello' 输出"
echo "========================================"
echo ""

# 检测串口设备
if [ -e "/dev/ttyUSB0" ]; then
    PORT="/dev/ttyUSB0"
elif [ -e "/dev/ttyACM0" ]; then
    PORT="/dev/ttyACM0"
else
    echo "未检测到串口设备。"
    echo "请手动设置串口设备 (如 /dev/ttyUSB0):"
    read -p "串口设备: " PORT
fi

echo "使用串口: $PORT"
echo "按 Ctrl+A 然后按 X 退出 minicom"
echo ""

# 使用 minicom 显示串口输出
if command -v minicom &> /dev/null; then
    sudo minicom -D "$PORT" -b 115200 -o
elif command -v picocom &> /dev/null; then
    sudo picocom -b 115200 "$PORT"
else
    echo "请安装 minicom 或 picocom:"
    echo "  sudo apt-get install minicom"
    echo "  或"
    echo "  sudo apt-get install picocom"
    echo ""
    echo "然后运行:"
    echo "  sudo minicom -D $PORT -b 115200"
fi
