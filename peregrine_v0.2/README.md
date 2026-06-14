# Peregrine v0.2

## 项目定位

基于v0.1的FPGA可综合版本。目标是补全所有RTL模块，使其可以通过Vivado综合并在FPGA开发板上验证。

## 相比v0.1的改进

- 补全top.sv中所有未连接的信号
- 完善dcache.sv状态机和写命中处理
- 完善mshr.sv多条目跟踪和数据返回
- 补全srb.sv分配时的元数据写入
- 添加XDC约束文件模板
- 添加Vivado TCL构建脚本

## 代码命名规范

- 全小写英文变量名，下划线分隔
- 输入信号后缀 `_i`，输出信号后缀 `_o`
- 模块间信号前缀为产生模块的缩写

## 目录结构

```
peregrine_v0.2/
├── rtl/
│   ├── top/          # 顶层模块
│   ├── frontend/     # 前端：PC、分支预测、I-Cache、ITCM
│   ├── decode/       # 译码：译码器、依赖检测、DAE分裂器
│   ├── execute/      # 执行：ALU、BRU、乘除法、旁路网络、寄存器堆
│   ├── memory/       # 存储：D-Cache、MSHR、TCM、AXI接口
│   ├── commit/       # 提交：SRB、Store Buffer、Writeback同步
│   ├── control/      # 控制：冲刷控制器、异常处理、性能计数器
│   └── include/      # 公共包定义
├── testbench/
│   ├── module_tb/    # 模块级测试
│   └── system_tb/    # 系统级测试
├── scripts/          # Vivado TCL脚本
└── constraints/      # XDC约束文件
```

## FPGA目标

- 器件：Xilinx 7系列 (Artix-7/Kintex-7)
- 时钟：100MHz
- 接口：AXI4 Master
