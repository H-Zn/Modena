// stride_prefetcher.sv
import cpu_pkg::*;

module stride_prefetcher #(
    parameter RPT_DEPTH = 16
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    // 访存提交监控
    input  logic        commit_valid_i,
    input  logic [31:0] commit_pc_i,
    input  logic [31:0] commit_addr_i,
    input  logic        commit_is_load_i,

    // 预取请求输出 (低优先级)
    output logic        prefetch_valid_o,
    output logic [31:0] prefetch_addr_o,
    input  logic        prefetch_ready_i
);

    typedef struct packed {
        logic        valid;
        logic [31:0] last_pc;
        logic [31:0] last_addr;
        logic [31:0] stride;
        logic [ 1:0] conf;   // 置信度 (2-bit 饱和)
    } rpt_entry_t;

    rpt_entry_t rpt [0:RPT_DEPTH-1];
    logic [$clog2(RPT_DEPTH)-1:0] rpt_idx;

    assign rpt_idx = commit_pc_i[$clog2(RPT_DEPTH)+1:2]; // 简单索引

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < RPT_DEPTH; i++) rpt[i].valid <= 1'b0;
            prefetch_valid_o <= 1'b0;
        end else if (flush_i) begin
            for (int i = 0; i < RPT_DEPTH; i++) rpt[i].valid <= 1'b0;
            prefetch_valid_o <= 1'b0;
        end else begin
            prefetch_valid_o <= 1'b0;
            if (commit_valid_i && commit_is_load_i) begin
                rpt_entry_t entry = rpt[rpt_idx];
                if (entry.valid && entry.last_pc == commit_pc_i) begin
                    // 计算步长并更新置信度
                    logic [31:0] new_stride = commit_addr_i - entry.last_addr;
                    if (new_stride == entry.stride) begin
                        if (entry.conf != 2'b11) entry.conf <= entry.conf + 1;
                    end else begin
                        if (entry.conf != 2'b00) entry.conf <= entry.conf - 1;
                        else entry.stride <= new_stride;
                    end
                    entry.last_addr <= commit_addr_i;
                    rpt[rpt_idx] <= entry;

                    // 预取发起
                    if (entry.conf >= 2'b10) begin
                        prefetch_valid_o <= 1'b1;
                        prefetch_addr_o  <= commit_addr_i + entry.stride;
                    end
                end else begin
                    // 分配新条目
                    rpt[rpt_idx].valid    <= 1'b1;
                    rpt[rpt_idx].last_pc  <= commit_pc_i;
                    rpt[rpt_idx].last_addr<= commit_addr_i;
                    rpt[rpt_idx].stride   <= 32'h0;
                    rpt[rpt_idx].conf     <= 2'b00;
                end
            end
        end
    end

endmodule