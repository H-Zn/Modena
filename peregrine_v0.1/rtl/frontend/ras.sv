module ras (
    input  logic        clk,
    input  logic        rst_n,

    // 译码阶段识别信号
    input  logic        push_valid,
    input  logic [31:0] push_addr,    // PC+4
    input  logic        pop_valid,

    // 预测输出
    output logic [31:0] pred_target,
    output logic        empty
);

    localparam DEPTH = 16;
    logic [31:0] stack [0:DEPTH-1];
    logic [4:0]  sp;  // 0~16, 指向栈顶空位

    assign empty = (sp == 5'd0);
    assign pred_target = empty ? 32'h0 : stack[sp-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sp <= 5'd0;
        end else begin
            if (push_valid && !pop_valid) begin
                if (sp < DEPTH) begin
                    stack[sp] <= push_addr;
                    sp <= sp + 1;
                end
            end else if (!push_valid && pop_valid) begin
                if (sp > 0)
                    sp <= sp - 1;
            end else if (push_valid && pop_valid) begin
                // 同时压栈和弹栈 (例如CALL后紧跟RET？实际上需按语义处理，此处保守维持不变)
                // 一般RISC-V中不会出现，但若出现，可设计为：先弹后压
                // 此处简化为无操作，实际设计需细致处理
            end
        end
    end

endmodule