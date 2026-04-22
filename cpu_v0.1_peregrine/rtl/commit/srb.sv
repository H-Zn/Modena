// srb.sv
`timescale 1ns / 1ps
import cpu_pkg::*;

module srb #(
    parameter DEPTH = 16
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    // 分配接口（来自 ID 阶段，指令发射时）
    input  logic        alloc_en_i,
    output logic [4:0]  alloc_idx_o,     // 分配的条目索引
    output logic        alloc_full_o,

    // 结果写回接口（来自各执行岛）
    input  logic        result_wr_en_i,
    input  logic [4:0]  result_idx_i,    // 对应 SRB 条目索引
    input  logic [31:0] result_data_i,
    input  logic        result_exception_i,
    input  exc_code_t   result_exc_code_i,

    // 提交接口（写回寄存器堆）
    output logic        commit_valid_o,
    output logic [ 4:0] commit_rd_addr_o,
    output logic [31:0] commit_rd_data_o,
    output logic        commit_rd_wen_o,

    // Store 提交确认（至 Store Buffer）
    output logic        store_commit_o,
    output logic [ 2:0] store_commit_idx_o, // Store Buffer 索引

    // 异常触发
    output logic        exc_req_o,
    output logic [31:0] exc_pc_o,
    output exc_code_t   exc_code_o,

    // 停顿控制
    output logic        stall_wb_o,

    // 性能事件
    output logic        instret_event_o
);

    srb_entry_t buffer [0:DEPTH-1];
    logic [4:0] wr_ptr;  // 尾指针（分配用）
    logic [4:0] rd_ptr;  // 头指针（提交用）
    logic [4:0] count;   // 已占用条目数

    assign alloc_idx_o   = wr_ptr;
    assign alloc_full_o  = (count == DEPTH);
    assign stall_wb_o    = (count > 0) && !buffer[rd_ptr].ready && !buffer[rd_ptr].exception;

    // 提交输出
    assign commit_valid_o   = (count > 0) && buffer[rd_ptr].ready && !buffer[rd_ptr].exception && !flush_i;
    assign commit_rd_addr_o = buffer[rd_ptr].rd_addr;
    assign commit_rd_data_o = buffer[rd_ptr].result;
    assign commit_rd_wen_o  = buffer[rd_ptr].rd_wen;

    // Store 提交确认（当头部是 Store 指令且 rd_wen=0 时发出）
    assign store_commit_o   = commit_valid_o && (buffer[rd_ptr].rd_wen == 1'b0);
    assign store_commit_idx_o = 3'b000; // 需根据实际 Store Buffer 索引映射，此处简化

    // 异常触发
    assign exc_req_o  = (count > 0) && buffer[rd_ptr].exception && !flush_i;
    assign exc_pc_o   = buffer[rd_ptr].pc;
    assign exc_code_o = buffer[rd_ptr].exc_code;

    assign instret_event_o = commit_valid_o;

    // 分配与结果接收
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) buffer[i] <= '0;
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else if (flush_i) begin
            for (int i = 0; i < DEPTH; i++) buffer[i].valid <= 1'b0;
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            // 分配新条目（指令发射时）
            if (alloc_en_i && !alloc_full_o) begin
                buffer[wr_ptr].valid   <= 1'b1;
                buffer[wr_ptr].ready   <= 1'b0;
                buffer[wr_ptr].exception <= 1'b0;
                // 其他字段（rd_addr, pc等）由外部在分配时写入，此处不覆盖
                wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
            end

            // 接收执行岛结果
            if (result_wr_en_i) begin
                buffer[result_idx_i].result   <= result_data_i;
                buffer[result_idx_i].ready    <= 1'b1;
                buffer[result_idx_i].exception<= result_exception_i;
                buffer[result_idx_i].exc_code <= result_exc_code_i;
            end

            // 提交：头部释放
            if (commit_valid_o) begin
                buffer[rd_ptr].valid <= 1'b0;
                rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
            end

            // 更新计数
            if (alloc_en_i && !alloc_full_o && !commit_valid_o)
                count <= count + 1'b1;
            else if (!(alloc_en_i && !alloc_full_o) && commit_valid_o)
                count <= count - 1'b1;
        end
    end

    // 分配时写入其他信息的接口（rd_addr, pc 等）可通过独立端口或直接连线，此处省略

endmodule