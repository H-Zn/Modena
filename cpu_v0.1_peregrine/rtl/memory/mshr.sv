// mshr.sv
import cpu_pkg::*;

module mshr #(
    parameter NUM_ENTRIES = 4
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    // 分配接口 (来自 D-Cache)
    input  logic        alloc_valid_i,
    input  logic [31:0] alloc_addr_i,
    input  logic        alloc_is_write_i,
    output logic        alloc_ready_o,
    output logic [1:0]  alloc_id_o,      // 分配的条目号

    // 填充接口 (来自 AXI)
    output logic        fill_req_valid_o,
    output logic [31:0] fill_req_addr_o,
    output logic        fill_req_is_write_o,
    input  logic        fill_req_ready_i,

    input  logic        fill_data_valid_i,
    input  logic [31:0] fill_data_i,
    input  logic        fill_data_last_i,

    // 唤醒与完成通知
    output logic        fill_done_valid_o,
    output logic [1:0]  fill_done_id_o
);

    typedef struct packed {
        logic        valid;
        logic [31:0] line_addr;      // 对齐地址
        logic        is_write;
        logic [ 7:0] sub_req_mask;   // 待返回的字掩码 (每字1位)
        logic [ 7:0] wait_mask;      // 等待的 Load/Store 掩码 (预留)
    } mshr_entry_t;

    mshr_entry_t entries [0:NUM_ENTRIES-1];
    logic [1:0] alloc_ptr;

    assign alloc_ready_o = !entries[alloc_ptr].valid;
    assign alloc_id_o    = alloc_ptr;

    // 分配与合并逻辑
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENTRIES; i++)
                entries[i].valid <= 1'b0;
            alloc_ptr <= '0;
        end else if (flush_i) begin
            for (int i = 0; i < NUM_ENTRIES; i++)
                entries[i].valid <= 1'b0;
            alloc_ptr <= '0;
        end else begin
            if (alloc_valid_i && alloc_ready_o) begin
                entries[alloc_ptr].valid      <= 1'b1;
                entries[alloc_ptr].line_addr  <= alloc_addr_i;
                entries[alloc_ptr].is_write   <= alloc_is_write_i;
                entries[alloc_ptr].sub_req_mask <= 8'hFF; // 等待全部8字
                entries[alloc_ptr].wait_mask  <= '0;
                alloc_ptr <= (alloc_ptr == NUM_ENTRIES-1) ? '0 : alloc_ptr + 1'b1;
            end

            // 数据返回处理
            if (fill_data_valid_i) begin
                // 简化：假设所有返回属于当前活跃条目，此处需通过 ID 索引
                // ...
                if (fill_data_last_i)
                    entries[alloc_ptr].valid <= 1'b0; // 完成释放
            end
        end
    end

    // 填充请求发起 (新分配时)
    assign fill_req_valid_o = alloc_valid_i && alloc_ready_o;
    assign fill_req_addr_o  = alloc_addr_i;
    assign fill_req_is_write_o = alloc_is_write_i;

    // 完成通知
    assign fill_done_valid_o = fill_data_valid_i && fill_data_last_i;
    assign fill_done_id_o    = alloc_ptr; // 简化

endmodule