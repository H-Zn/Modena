// flush_controller.sv
`timescale 1ns / 1ps
import cpu_pkg::*;

module flush_controller (
    input  logic        clk,
    input  logic        rst_n,

    // 冲刷请求源
    input  logic        exc_req_i,         // 来自 exception_handler
    input  logic [31:0] exc_target_i,      // 异常目标PC (mtvec/stvec)
    input  logic        mispred_req_i,     // 来自 BRU
    input  logic [31:0] mispred_target_i,  // 分支正确目标
    input  logic        fencei_req_i,      // 来自 decoder (FENCE.I)
    input  logic        debug_req_i,       // 调试请求 (预留)

    // 冲刷输出 (至各流水级寄存器)
    output logic        flush_if_o,
    output logic        flush_id_o,
    output logic        flush_ex1_o,
    output logic        flush_ex2_o,

    // PC 重定向
    output logic        pc_redirect_valid_o,
    output logic [31:0] pc_redirect_target_o,

    // 性能计数器事件
    output logic        flush_event_o,
    output logic        mispred_event_o
);

    // 冲刷源锁存 (冲刷持续一个周期)
    logic        flush_pending;
    flush_src_t  flush_src;
    logic [31:0] flush_target_pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_pending    <= 1'b0;
            flush_src        <= FLUSH_NONE;
            flush_target_pc  <= 32'h0;
        end else begin
            // 优先级仲裁: 异常 > 误预测 > fence.i > 调试
            if (exc_req_i) begin
                flush_pending   <= 1'b1;
                flush_src       <= FLUSH_EXCEPTION;
                flush_target_pc <= exc_target_i;
            end else if (mispred_req_i) begin
                flush_pending   <= 1'b1;
                flush_src       <= FLUSH_MISPRED;
                flush_target_pc <= mispred_target_i;
            end else if (fencei_req_i) begin
                flush_pending   <= 1'b1;
                flush_src       <= FLUSH_FENCEI;
                flush_target_pc <= 32'h0;  // 由外部处理，或使用 pc+4
            end else if (debug_req_i) begin
                flush_pending   <= 1'b1;
                flush_src       <= FLUSH_FENCEI; // 复用
                flush_target_pc <= 32'h0;
            end else begin
                flush_pending <= 1'b0;
            end
        end
    end

    // 冲刷范围控制
    always_comb begin
        flush_if_o  = 1'b0;
        flush_id_o  = 1'b0;
        flush_ex1_o = 1'b0;
        flush_ex2_o = 1'b0;
        if (flush_pending) begin
            case (flush_src)
                FLUSH_EXCEPTION: begin
                    // 异常：冲刷异常指令及其后所有
                    flush_if_o  = 1'b1;
                    flush_id_o  = 1'b1;
                    flush_ex1_o = 1'b1;
                    flush_ex2_o = 1'b1; // EX2 也需冲刷（若异常在 EX2 之后检测）
                end
                FLUSH_MISPRED: begin
                    // 分支误预测：IF, ID, EX1 被冲刷
                    flush_if_o  = 1'b1;
                    flush_id_o  = 1'b1;
                    flush_ex1_o = 1'b1;
                    flush_ex2_o = 1'b0;
                end
                FLUSH_FENCEI: begin
                    flush_if_o  = 1'b1;
                    flush_id_o  = 1'b1;
                    flush_ex1_o = 1'b1;
                    flush_ex2_o = 1'b0;
                end
                default: ;
            endcase
        end
    end

    // PC 重定向输出
    assign pc_redirect_valid_o = flush_pending;
    assign pc_redirect_target_o = flush_target_pc;

    // 性能事件
    assign flush_event_o = flush_pending;
    assign mispred_event_o = (flush_src == FLUSH_MISPRED) && flush_pending;

endmodule