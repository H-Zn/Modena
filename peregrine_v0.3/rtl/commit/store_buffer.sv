// store_buffer.sv
import cpu_pkg::*;

module store_buffer #(
    parameter DEPTH = 8
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    // 写端口（EX3 阶段推入）
    input  logic        wr_en_i,
    input  logic [31:0] wr_addr_i,
    input  logic [31:0] wr_data_i,
    input  logic [ 3:0] wr_mask_i,
    output logic        full_o,

    // 提交确认（来自 SRB）
    input  logic        commit_i,
    input  logic [ 2:0] commit_idx_i,

    // 转发接口（MEM 阶段 Load 查询）
    input  logic [31:0] load_addr_i,
    input  logic [ 1:0] load_width_i,
    output logic        forward_hit_o,
    output logic [31:0] forward_data_o,

    // 写回接口（至 writeback_sync）
    input  logic        wb_rd_en_i,      // 读使能（弹出头部）
    output stb_entry_t  wb_rd_data_o,
    output logic        empty_o,

    // 冲刷清除（未提交条目）
    input  logic        clear_uncommitted_i
);

    stb_entry_t buffer [0:DEPTH-1];
    logic [2:0] wr_ptr, rd_ptr;
    logic [2:0] count;

    assign empty_o = (count == 0);
    assign full_o  = (count == DEPTH);
    assign wb_rd_data_o = buffer[rd_ptr];

    // Store-to-Load 转发
    always_comb begin
        forward_hit_o = 1'b0;
        forward_data_o = 32'h0;
        // 从最早（靠近 rd_ptr）到最新查找匹配
        for (int i = 0; i < DEPTH; i++) begin
            logic [2:0] idx = (rd_ptr + i) % DEPTH;
            if (buffer[idx].valid && buffer[idx].committed) begin
                // 地址完全匹配简化处理（实际需考虑掩码重叠）
                if (buffer[idx].addr == load_addr_i) begin
                    forward_hit_o = 1'b1;
                    forward_data_o = buffer[idx].data;
                    break;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) buffer[i].valid <= 1'b0;
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else if (flush_i || clear_uncommitted_i) begin
            // 清空所有未提交条目（committed=0）
            for (int i = 0; i < DEPTH; i++) begin
                if (!buffer[i].committed)
                    buffer[i].valid <= 1'b0;
            end
            // 注意：指针回退复杂，简化起见，实际需维护未提交计数并调整
        end else begin
            // 推入新 Store
            if (wr_en_i && !full_o) begin
                buffer[wr_ptr].valid    <= 1'b1;
                buffer[wr_ptr].addr     <= wr_addr_i;
                buffer[wr_ptr].data     <= wr_data_i;
                buffer[wr_ptr].byte_mask<= wr_mask_i;
                buffer[wr_ptr].committed<= 1'b0;
                wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
            end

            // 提交标志更新
            if (commit_i) begin
                buffer[commit_idx_i].committed <= 1'b1;
            end

            // 写回释放（头部弹出）
            if (wb_rd_en_i && !empty_o) begin
                buffer[rd_ptr].valid <= 1'b0;
                rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
            end

            // 计数更新
            if (wr_en_i && !full_o && !(wb_rd_en_i && !empty_o))
                count <= count + 1'b1;
            else if (!(wr_en_i && !full_o) && wb_rd_en_i && !empty_o)
                count <= count - 1'b1;
        end
    end

endmodule