#!/bin/bash
# ============================================================================
# Peregrine CPU - Linux 完整构建与测试脚本
# Usage: chmod +x build_and_test.sh && ./build_and_test.sh
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIVADO_PROJ="$PROJECT_DIR/vivado_proj"

echo "========================================"
echo "   Peregrine CPU FPGA Build & Test"
echo "========================================"
echo ""

# 1. 构建
echo "[1/5] Building FPGA design..."
cd "$SCRIPT_DIR"
bash build_linux.sh

# 2. 检查 bitstream
BITSTREAM="$VIVADO_PROJ/peregrine_fpga.runs/impl_1/peregrine_top.bit"
if [ ! -f "$BITSTREAM" ]; then
    echo "ERROR: Bitstream not found at $BITSTREAM"
    exit 1
fi
echo "[2/5] Bitstream ready."

# 3. 烧录
echo "[3/5] Programming FPGA..."
cd "$SCRIPT_DIR"
vivado -mode tcl -source program.tcl

# 4. 等待用户连接串口
echo ""
echo "[4/5] FPGA programmed!"
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
echo "[5/5] 按 Enter 继续查看串口输出, 或 Ctrl+C 退出..."
read -p ""

# 5. 检测串口并显示输出
echo ""
echo "========================================"
echo "  以下应该是 'Hello' 输出"
echo "========================================"
echo ""

# 检测串口设备
PORT=""
for p in /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyUSB1 /dev/ttyACM1; do
    if [ -e "$p" ]; then
        PORT="$p"
        break
    fi
done

if [ -z "$PORT" ]; then
    echo "未检测到串口设备。"
    echo "请手动输入串口设备路径 (如 /dev/ttyUSB0):"
    read -p "串口设备: " PORT
fi

echo "使用串口: $PORT (115200 8N1)"
echo "按 Ctrl+A 然后按 X 退出 minicom"
echo ""

# 使用 minicom 显示串口输出
if command -v minicom &> /dev/null; then
    sudo minicom -D "$PORT" -b 115200 -o
elif command -v picocom &> /dev/null; then
    sudo picocom -b 115200 "$PORT"
elif command -v screen &> /dev/null; then
    sudo screen "$PORT" 115200
else
    echo "未找到串口工具。请安装:"
    echo "  sudo apt-get install minicom"
    echo ""
    echo "然后运行:"
    echo "  sudo minicom -D $PORT -b 115200"
fi
