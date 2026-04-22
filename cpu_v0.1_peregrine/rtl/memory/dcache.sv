// dcache.sv
`timescale 1ns / 1ps
import cpu_pkg::*;

module dcache #(
    parameter CACHE_SIZE   = 16*1024,  // 16KB
    parameter LINE_SIZE    = 32,       // 32 bytes
    parameter WAYS         = 4
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,       // FENCE.I 冲刷

    // 来自 MEM 阶段的访存请求
    input  logic        req_valid_i,
    input  mem_req_type_t req_type_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [ 3:0] req_wmask_i,
    input  logic        req_is_atomic_i,
    input  logic [ 3:0] req_atomic_op_i,

    // 响应
    output logic        rsp_valid_o,
    output logic [31:0] rsp_rdata_o,
    output logic        rsp_miss_o,     // 缺失标志

    // MSHR 接口 (缺失时使用)
    output logic        mshr_alloc_valid_o,
    output logic [31:0] mshr_alloc_addr_o,
    output logic        mshr_alloc_is_write_o,
    input  logic        mshr_alloc_ready_i,
    input  logic        mshr_alloc_id_i, // 分配的条目号

    // MSHR 填充接口 (数据返回时)
    input  logic        mshr_fill_valid_i,
    input  logic [ 1:0] mshr_fill_id_i,
    input  logic [31:0] mshr_fill_addr_i,
    input  logic [31:0] mshr_fill_data_i,
    input  logic        mshr_fill_last_i,

    // 写回接口 (至 Write Buffer / AXI)
    output logic        wb_req_valid_o,
    output logic [31:0] wb_req_addr_o,
    output logic [31:0] wb_req_data_o,
    output logic [ 3:0] wb_req_mask_o,
    input  logic        wb_req_ready_i
);

    localparam NUM_SETS = CACHE_SIZE / (LINE_SIZE * WAYS); // 128
    localparam INDEX_BITS = $clog2(NUM_SETS);   // 7
    localparam OFFSET_BITS = $clog2(LINE_SIZE); // 5
    localparam TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS; // 20

    // Cache 存储结构 (简化: 使用多维数组，实际会综合为 BRAM)
    typedef struct packed {
        logic [TAG_BITS-1:0] tag;
        logic                valid;
        logic                dirty;
    } tag_entry_t;

    tag_entry_t tag_ram [0:NUM_SETS-1][0:WAYS-1];
    logic [LINE_SIZE*8-1:0] data_ram [0:NUM_SETS-1][0:WAYS-1];
    logic [WAYS-2:0] plru_bits [0:NUM_SETS-1]; // 树状 PLRU (3 bits for 4 ways)

    // 访问地址分解
    logic [TAG_BITS-1:0]   req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    logic [OFFSET_BITS-1:0] req_off;
    assign {req_tag, req_idx, req_off} = req_addr_i[31:2];

    // 命中检测
    logic hit;
    logic [1:0] hit_way;
    always_comb begin
        hit = 1'b0;
        hit_way = 2'b00;
        for (int w = 0; w < WAYS; w++) begin
            if (tag_ram[req_idx][w].valid && tag_ram[req_idx][w].tag == req_tag) begin
                hit = 1'b1;
                hit_way = w;
                break;
            end
        end
    end

    // 读数据输出 (命中)
    logic [31:0] rdata_hit;
    always_comb begin
        rdata_hit = 32'h0;
        if (hit) begin
            case (req_off[4:2])
                3'd0: rdata_hit = data_ram[req_idx][hit_way][31:0];
                3'd1: rdata_hit = data_ram[req_idx][hit_way][63:32];
                3'd2: rdata_hit = data_ram[req_idx][hit_way][95:64];
                3'd3: rdata_hit = data_ram[req_idx][hit_way][127:96];
                3'd4: rdata_hit = data_ram[req_idx][hit_way][159:128];
                3'd5: rdata_hit = data_ram[req_idx][hit_way][191:160];
                3'd6: rdata_hit = data_ram[req_idx][hit_way][223:192];
                3'd7: rdata_hit = data_ram[req_idx][hit_way][255:224];
            endcase
        end
    end

    // 缺失与命中响应
    assign rsp_valid_o = req_valid_i && hit && !flush_i;
    assign rsp_rdata_o = rdata_hit;
    assign rsp_miss_o  = req_valid_i && !hit;

    // MSHR 分配请求
    assign mshr_alloc_valid_o = req_valid_i && !hit && !flush_i;
    assign mshr_alloc_addr_o  = {req_addr_i[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    assign mshr_alloc_is_write_o = (req_type_i == MEM_REQ_STORE);

    // 状态机 (处理填充、写回等，简化实现)
    // 填充: 当 mshr_fill_valid_i 有效时，将数据写入 data_ram 并更新 tag
    always_ff @(posedge clk) begin
        if (mshr_fill_valid_i) begin
            logic [INDEX_BITS-1:0] fill_idx;
            logic [TAG_BITS-1:0] fill_tag;
            {fill_tag, fill_idx} = mshr_fill_addr_i[31:OFFSET_BITS];
            // 找到替换路 (由 MSHR 指定或采用 PLRU)
            logic [1:0] fill_way = plru_bits[fill_idx][0] ? 2'b01 : 2'b00; // 简化
            // 更新 tag 和数据
            tag_ram[fill_idx][fill_way].tag   <= fill_tag;
            tag_ram[fill_idx][fill_way].valid <= 1'b1;
            tag_ram[fill_idx][fill_way].dirty <= mshr_alloc_is_write_o; // 写缺失标记脏
            // 数据写入: 根据填充地址偏移逐字写入 (此处简化，实际需循环)
            // ...
        end
    end

    // 写命中处理 (此处省略详细写更新逻辑)

endmodule