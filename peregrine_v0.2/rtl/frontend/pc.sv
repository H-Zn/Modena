module pc_gen (
    input  logic        clk,
    input  logic        rst_n,

    // 预测接口
    input  logic        pred_dir,
    input  logic [31:0] pred_target,
    input  logic        fold_en,

    // 冲刷接口
    input  logic        flush,
    input  logic [31:0] flush_target,

    // 停顿接口
    input  logic        stall,

    // 输出
    output logic [31:0] pc
);

    logic [31:0] next_pc;

    always_comb 
    begin
        if (flush)
            next_pc = flush_target;
        else if (fold_en)
            next_pc = pred_target;
        else if (pred_dir)
            next_pc = pred_target;
        else
            next_pc = pc + 32'd4;
    end

    always_ff @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n)
            pc <= 32'h0;
        else if (!stall)
            pc <= next_pc;
    end

endmodule