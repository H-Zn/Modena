//分支折叠器
"""
本模块是通过感知器预测器与btb模块的信息，折叠分支指令

"""
module branch_floder(
    input logic if_branch,//是否是分支指令
    input logic pred_dir,//预测的分支方向,1跳转，0不跳转
    input logic [7:0] pred_conf,//预测的置信度;
    input logic btb_hit,//btb是否命中
    input logic [31:0] btb_target,//btb预测的目标地址

    output logic fold_en,//分支折叠使能信号,1时启分支折叠，0时不启用
    output logic [31:0] fold_target
);
//模块内参数，可调
localparam THRESHOLD = 8'd64;
//分支折叠使能条件：是分支指令，预测为跳转，btb命中，且预测置信度大于等于阈值
assign fold_en = is_branch && pred_dir && btb_hit && (conf >= THRESHOLD);
assign fold_target = btb_target;

    
endmodule