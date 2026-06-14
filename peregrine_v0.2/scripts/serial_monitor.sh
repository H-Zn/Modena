#!/bin/bash
# ============================================================================
# 串口监听脚本
# Usage: ./serial_monitor.sh [port] [baud]
# ============================================================================

PORT="${1:-/dev/ttyUSB0}"
BAUD="${2:-115200}"

echo "========================================="
echo "  Peregrine CPU Serial Monitor"
echo "  Port: $PORT"
echo "  Baud: $BAUD"
echo "========================================="
echo ""

# 自动检测串口
if [ ! -e "$PORT" ]; then
    echo "串口 $PORT 不存在，正在检测..."
    for p in /dev/ttyUSB0 /dev/ttyACM0 /dev/ttyUSB1 /dev/ttyACM1; do
        if [ -e "$p" ]; then
            PORT="$p"
            echo "找到串口: $PORT"
            break
        fi
    done
fi

if [ ! -e "$PORT" ]; then
    echo "错误: 未找到串口设备"
    echo "请检查USB线是否连接"
    exit 1
fi

# 设置串口参数
sudo stty -F "$PORT" $BAUD cs8 -cstopb -parenb -crtscts -echo

echo "监听中... (Ctrl+C 退出)"
echo "-----------------------------------------"

# 读取串口输出
sudo cat "$PORT"
