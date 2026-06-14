#!/bin/bash
mkdir -p build_tmp
rm -rf build_tmp/*
cd build_tmp

# 编译
xvlog -sv \
    ../../rtl/include/cpu_pkg.sv \
    ../../rtl/execute/alu_island.sv \
    ../../testbench/module_tb/execute/alu_island_tb.sv \
    -log mpile.log

#  elaboration
# 第一行写测试.sv
# 第二行写仿真文件名

xelab -debug all alu_island_tb \
    -snapshot sim_alu1 \
    -log elab.log

# 运行仿真
# 改仿真文件名
xsim sim_alu1 -runall -log build_tmp/sim.log

cd ..
rm -rf build_tmp/xsim.dir build_tmp/work build_tmp/*.jou build_tmp/*.wdb
