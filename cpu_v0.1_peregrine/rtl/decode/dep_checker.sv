// dep_checker.sv
module dep_checker (
    input  logic [4:0] rs1_addr_i,
    input  logic [4:0] rs2_addr_i,
    input  logic       rs1_used_i,
    input  logic       rs2_used_i,
    input  logic [4:0] rd_ex1_i,
    input  logic       rd_wen_ex1_i,
    input  logic [4:0] rd_ex2_i,
    input  logic       rd_wen_ex2_i,
    input  logic [4:0] rd_ex3_i,
    input  logic       rd_wen_ex3_i,
    input  logic       load_miss_i,        // Load/Store miss
    input  logic       mul_div_busy_i,     // M扩展忙
    input  logic       csr_busy_i,         // CSR操作忙 (Zicsr)
    input  logic       atomic_busy_i,      // A扩展原子操作忙
    output logic       stall_o
);

    // 待写回寄存器跟踪
    wire [4:0] pending_rd [0:2];
    wire [2:0] pending_wen;
    assign pending_rd[0] = rd_ex1_i;
    assign pending_rd[1] = rd_ex2_i;
    assign pending_rd[2] = rd_ex3_i;
    assign pending_wen[0] = rd_wen_ex1_i && (rd_ex1_i != 5'd0);
    assign pending_wen[1] = rd_wen_ex2_i && (rd_ex2_i != 5'd0);
    assign pending_wen[2] = rd_wen_ex3_i && (rd_ex3_i != 5'd0);

    // RAW检测
    logic rs1_raw, rs2_raw;
    always_comb begin
        rs1_raw = 1'b0;
        rs2_raw = 1'b0;
        if (rs1_used_i && rs1_addr_i != 5'd0) begin
            for (int i = 0; i < 3; i++)
                if (pending_wen[i] && pending_rd[i] == rs1_addr_i)
                    rs1_raw = 1'b1;
        end
        if (rs2_used_i && rs2_addr_i != 5'd0) begin
            for (int i = 0; i < 3; i++)
                if (pending_wen[i] && pending_rd[i] == rs2_addr_i)
                    rs2_raw = 1'b1;
        end
    end

    // 停顿条件 (简化：任何RAW均需停顿，实际配合旁路可消除部分)
    assign stall_o = (rs1_raw || rs2_raw) ||
                     load_miss_i || mul_div_busy_i || csr_busy_i || atomic_busy_i;

endmodule