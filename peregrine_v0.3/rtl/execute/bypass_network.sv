// bypass_network.sv
module bypass_network (
    // 源寄存器地址
    input  logic [4:0] rs1_addr_i,
    input  logic [4:0] rs2_addr_i,
    // 寄存器堆读出值
    input  logic [31:0] rf_rs1_data_i,
    input  logic [31:0] rf_rs2_data_i,

    // 旁路源：EX2 结果（来自 ALU/MUL/BRU）
    input  logic [4:0]  ex2_rd_i,
    input  logic        ex2_wen_i,
    input  logic [31:0] ex2_result_i,

    // 旁路源：EX3/MEM Load 结果
    input  logic [4:0]  mem_rd_i,
    input  logic        mem_wen_i,
    input  logic [31:0] mem_result_i,

    // 旁路源：SRB 写回值（当与读同周期时）
    input  logic [4:0]  wb_rd_i,
    input  logic        wb_wen_i,
    input  logic [31:0] wb_result_i,

    // 最终操作数输出
    output logic [31:0] op1_o,
    output logic [31:0] op2_o
);

    // 操作数1旁路选择
    always_comb begin
        op1_o = rf_rs1_data_i;
        if (rs1_addr_i != 5'd0) begin
            if (ex2_wen_i && ex2_rd_i == rs1_addr_i)
                op1_o = ex2_result_i;
            else if (mem_wen_i && mem_rd_i == rs1_addr_i)
                op1_o = mem_result_i;
            else if (wb_wen_i && wb_rd_i == rs1_addr_i)
                op1_o = wb_result_i;
        end
    end

    // 操作数2旁路选择
    always_comb begin
        op2_o = rf_rs2_data_i;
        if (rs2_addr_i != 5'd0) begin
            if (ex2_wen_i && ex2_rd_i == rs2_addr_i)
                op2_o = ex2_result_i;
            else if (mem_wen_i && mem_rd_i == rs2_addr_i)
                op2_o = mem_result_i;
            else if (wb_wen_i && wb_rd_i == rs2_addr_i)
                op2_o = wb_result_i;
        end
    end

endmodule