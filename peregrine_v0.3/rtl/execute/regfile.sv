// regfile.sv
module regfile (
    input  logic        clk,

    // 读端口1 (ID/EX1)
    input  logic [4:0]  rs1_addr_i,
    output logic [31:0] rs1_data_o,

    // 读端口2
    input  logic [4:0]  rs2_addr_i,
    output logic [31:0] rs2_data_o,

    // 写端口 (WB)
    input  logic        wr_en_i,
    input  logic [4:0]  rd_addr_i,
    input  logic [31:0] rd_data_i
);

    // 32x32 寄存器堆，x0 硬连线为0
    logic [31:0] regs [0:31];
    
    // 读操作（组合或时序，此处为组合以配合流水线，实际通常为读异步）
    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'h0 : regs[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'h0 : regs[rs2_addr_i];

    // 写操作
    always_ff @(posedge clk) begin
        if (wr_en_i && rd_addr_i != 5'd0)
            regs[rd_addr_i] <= rd_data_i;
    end

endmodule