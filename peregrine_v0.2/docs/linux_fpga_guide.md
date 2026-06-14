# Linux Vivado 上板测试指南

## 1. 环境准备

### 1.1 Linux Vivado 安装
```bash
# 安装 Vivado (版本 2023.2 或相近版本)
# 下载地址: https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vivado-tools.html

# 设置环境变量 (安装后)
source /opt/Xilinx/Vivado/2023.2/settings64.sh
```

### 1.2 USB 驱动
```bash
# 检查 USB 调试器 (通常是 Digilent USB-JTAG 或 Platform Cable)
lsusb
# 应看到类似: Xilinx Platform Cable 或 Digilent Adept

# 如果没有权限，添加 udev 规则
sudo bash -c 'cat > /etc/udev/rules.d/52-xilinx.rules << EOF
SUBSYSTEM=="usb", ATTR{idVendor}=="03fd", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="1443", MODE="0444"
EOF'
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 1.3 串口工具
```bash
# 安装 minicom (Linux 串口工具)
sudo apt-get install minicom

# 或使用 picocom
sudo apt-get install picocom

# 或直接用 screen
sudo apt-get install screen
```

## 2. 修改引脚约束

### 2.1 查看手册获取引脚信息

**你需要从手册 PDF 中找到以下信息：**

| 信号 | 引脚号 | 说明 |
|------|--------|------|
| clk_i | ?? | 系统时钟输入 |
| rst_n_i | ?? | 复位按钮 |
| UART_TX | ?? | CPU 输出到 PC |
| UART_RX | ?? | PC 输入到 CPU |
| LED[0] | ?? | 用于调试 |
| UART_USB_TX | ?? | USB转串口芯片的TX(连到CPU RX) |
| UART_USB_RX | ?? | USB转串口芯片的RX(连到CPU TX) |

**常见开发板引脚参考（请以你的手册为准）：**

| 开发板 | 时钟 | UART TX | UART RX | 复位 |
|--------|------|---------|---------|------|
| 正点原子达芬奇 | E3(100MHz) | B7 | A9 | L19 |
| 正点原子开拓者 | Y18(100MHz) | N15 | N16 | P19 |
| 野火征途 | U14(50MHz) | B16 | A16 | G19 |
| 小梅哥ACX720 | H13(50MHz) | K3 | K1 | C3 |

### 2.2 更新 XDC 文件

编辑 `peregrine_v0.2/constraints/peregrine.xdc`，填入正确引脚：

```xdc
## ============================================================================
## 时钟 - 根据手册修改
## ============================================================================
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk_i]
set_property PACKAGE_PIN <时钟引脚> [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]

## ============================================================================
## 复位 - 根据手册修改
## ============================================================================
set_property PACKAGE_PIN <复位按钮引脚> [get_ports rst_n_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n_i]

## ============================================================================
## UART 串口 - 根据手册修改
## 注意: USB转串口芯片的TX连接到CPU的RX，反之亦然
## ============================================================================
set_property PACKAGE_PIN <UART_TX引脚> [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property PACKAGE_PIN <UART_RX引脚> [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

## ============================================================================
## LED 用于调试
## ============================================================================
set_property PACKAGE_PIN <LED0引脚> [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
```

## 3. 添加 UART 模块到 RTL

### 3.1 创建 UART TX 模块

在 `peregrine_v0.2/rtl/top/` 下创建 `uart_tx.sv`：

```systemverilog
// uart_tx.sv - 简单 UART 发送模块
module uart_tx #(
    parameter CLKS_PER_BIT = 868  // 100MHz / 115200 = 868
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic       tx_pin
);

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state;
    logic [3:0] bit_idx;
    logic [9:0] clk_cnt;
    logic [7:0] tx_reg;

    assign tx_ready = (state == IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            bit_idx <= 0;
            clk_cnt <= 0;
            tx_reg  <= 0;
            tx_pin  <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_valid) begin
                        state   <= START;
                        tx_reg  <= tx_data;
                        clk_cnt <= 0;
                    end
                end
                START: begin
                    tx_pin <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        state   <= DATA;
                        clk_cnt <= 0;
                        bit_idx <= 0;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    tx_pin <= tx_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        if (bit_idx == 7) begin
                            state <= STOP;
                        end else
                            bit_idx <= bit_idx + 1;
                        clk_cnt <= 0;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    tx_pin <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end

endmodule
```

### 3.2 在 top.sv 中例化 UART

在 `peregrine_v0.2/rtl/top/top.sv` 中添加：

```systemverilog
// 端口声明中添加:
output logic uart_tx,
input  logic uart_rx,
output logic [1:0] led

// 模块内部添加 UART TX 例化:
logic [7:0] uart_tx_data;
logic       uart_tx_valid;
logic       uart_tx_ready;

uart_tx #(.CLKS_PER_BIT(868)) uart_tx_inst (
    .clk      (clk),
    .rst_n    (rst_n),
    .tx_data  (uart_tx_data),
    .tx_valid (uart_tx_valid),
    .tx_ready (uart_tx_ready),
    .tx_pin   (uart_tx)
);

// 简单测试: 上电后发送 "Hello\n"
typedef enum logic [2:0] {
    S_IDLE,
    S_SEND_H, S_SEND_E, S_SEND_L1, S_SEND_L2, S_SEND_O, S_SEND_NL,
    S_DONE
} hello_state_t;

hello_state_t hello_state;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hello_state <= S_IDLE;
        uart_tx_valid <= 1'b0;
        uart_tx_data  <= 8'h0;
    end else begin
        uart_tx_valid <= 1'b0;
        case (hello_state)
            S_IDLE: begin
                if (uart_tx_ready) begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data  <= "H";
                    hello_state   <= S_SEND_E;
                end
            end
            S_SEND_E: begin
                if (uart_tx_ready) begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data  <= "e";
                    hello_state   <= S_SEND_L1;
                end
            end
            S_SEND_L1: begin
                if (uart_tx_ready) begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data  <= "l";
                    hello_state   <= S_SEND_L2;
                end
            end
            S_SEND_L2: begin
                if (uart_tx_ready) begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data  <= "l";
                    hello_state   <= S_SEND_O;
                end
            end
            S_SEND_O: begin
                if (uart_tx_ready) begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data  <= "o";
                    hello_state   <= S_SEND_NL;
                end
            end
            S_SEND_NL: begin
                if (uart_tx_ready) begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data  <= 8'h0A; // 换行
                    hello_state   <= S_DONE;
                end
            end
            S_DONE: begin
                hello_state <= S_IDLE; // 循环发送
            end
        endcase
    end
end

// LED 用于指示状态
assign led[0] = ~rst_n;  // 复位时亮
assign led[1] = |hello_state; // 发送时闪烁
```

## 4. Vivado 构建流程 (Linux)

### 4.1 创建工程
```bash
cd /path/to/peregrine_v0.2
vivado -mode batch -source scripts/create_project.tcl
```

### 4.2 综合
```bash
vivado -mode batch -source scripts/run_synth_impl.tcl
```

### 4.3 或使用 GUI
```bash
vivado
# Project Manager → Open Project → 选择 vivado_proj/peregrine_fpga.xpr
# Flow Navigator → Run Synthesis → Run Implementation → Generate Bitstream
```

## 5. 下载 bitstream 到开发板

### 5.1 通过 JTAG 下载
```bash
# 使用 Vivado Hardware Manager
vivado -mode batch -e "open_hw_manager; connect_hw_server; open_hw_target; set_property PROGRAM.FILE {vivado_proj/peregrine_fpga.runs/impl_1/peregrine_top.bit} [current_hw_device]; program_hw_devices [current_hw_device]"
```

### 5.2 或使用 GUI
```
Flow Navigator → Open Hardware Manager → Auto Connect → Program Device
选择 bitstream 文件: vivado_proj/peregrine_fpga.runs/impl_1/peregrine_top.bit
```

## 6. Tera Term 串口配置

### 6.1 连接开发板
1. 用 USB 线连接开发板的 USB-UART 口到电脑
2. 打开设备管理器，查看 COM 口号（Windows）或 `/dev/ttyUSB0`（Linux）

### 6.2 Tera Term 设置

**Windows (Tera Term 5):**
```
文件 → 新建连接 → 选择串口 (COMx) → 确定
设置 → 串口端口:
  - 波特率: 115200
  - 数据位: 8
  - 停止位: 1
  - 校验: 无
  - 流控: 无
```

**Linux (minicom):**
```bash
sudo minicom -s
# 设置 → 串口参数:
#   波特率: 115200
#   数据位: 8
#   停止位: 1
#   校验: 无
#   硬件流控: 否
#   软件流控: 否
# 串口设备: /dev/ttyUSB0

# 保存配置后退出，然后:
sudo minicom
```

**Linux (picocom):**
```bash
sudo picocom -b 115200 /dev/ttyUSB0
```

**Linux (screen):**
```bash
sudo screen /dev/ttyUSB0 115200
```

### 6.3 预期输出

上电后应看到:
```
Hello
Hello
Hello
...
```

## 7. 调试技巧

### 7.1 如果没有输出
1. 检查 COM 口号是否正确
2. 检查波特率是否匹配
3. 检查 TX/RX 是否接反
4. 用示波器/逻辑分析仪检查 TX 引脚是否有波形

### 7.2 LED 调试
```systemverilog
// 在 top.sv 中添加 LED 指示
assign led[0] = clk;        // 时钟指示（应常亮或闪烁）
assign led[1] = uart_tx;    // UART TX 活动指示
assign led[2] = uart_rx;    // UART RX 活动指示
```

### 7.3 生成 VCD 波形
```bash
# 在 Vivado 仿真中
# Settings → Simulation → Simulation Settings → Dump All Signals → VCD
```

## 8. 文件清单

```
peregrine_v0.2/
├── rtl/
│   └── top/
│       ├── top.sv          # 顶层 (已添加 UART)
│       ├── uart_tx.sv      # UART 发送模块 (新建)
│       └── clk_rst_manager.sv
├── constraints/
│   └── peregrine.xdc       # 引脚约束 (需更新)
├── scripts/
│   ├── create_project.tcl
│   ├── run_synth_impl.tcl
│   └── build.bat
└── sim/
    └── test_program.hex
```
