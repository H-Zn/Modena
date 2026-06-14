// writeback_sync.sv
import cpu_pkg::*;

module writeback_sync (
    input  logic        clk,
    input  logic        rst_n,

    // Store Buffer 接口
    output logic        stb_rd_en_o,
    input  stb_entry_t  stb_rd_data_i,
    input  logic        stb_empty_i,

    // D-Cache 写请求接口
    output logic        dcache_wr_req_o,
    output logic [31:0] dcache_wr_addr_o,
    output logic [31:0] dcache_wr_data_o,
    output logic [ 3:0] dcache_wr_mask_o,
    input  logic        dcache_wr_gnt_i,      // 写授权（空闲时响应）
    input  logic        dcache_wr_done_i,     // 写完成
    input  logic        dcache_wr_miss_i,     // 写缺失（需分配）

    // MSHR 接口（处理写缺失时的读分配）
    output logic        mshr_alloc_valid_o,
    output logic [31:0] mshr_alloc_addr_o,
    input  logic        mshr_alloc_ready_i,
    input  logic        mshr_fill_done_i
);

    typedef enum logic [1:0] {IDLE, REQ, WAIT_MISS, WAIT_DONE} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        stb_rd_en_o = 1'b0;
        dcache_wr_req_o = 1'b0;
        mshr_alloc_valid_o = 1'b0;
        case (state)
            IDLE: begin
                if (!stb_empty_i && stb_rd_data_i.committed) begin
                    stb_rd_en_o = 1'b1;      // 读出头条目（下一周期有效）
                    next_state = REQ;
                end
            end
            REQ: begin
                dcache_wr_req_o = 1'b1;
                if (dcache_wr_gnt_i) begin
                    if (dcache_wr_miss_i) begin
                        // 写缺失：需要分配 MSHR 读缺失行
                        mshr_alloc_valid_o = 1'b1;
                        next_state = WAIT_MISS;
                    end else begin
                        next_state = WAIT_DONE;
                    end
                end
            end
            WAIT_MISS: begin
                if (mshr_alloc_ready_i && mshr_fill_done_i)
                    next_state = REQ;  // 重新尝试写
            end
            WAIT_DONE: begin
                if (dcache_wr_done_i)
                    next_state = IDLE; // 条目已释放（由 Store Buffer 外部 rd_en 控制）
            end
        endcase
    end

    assign mshr_alloc_addr_o = {stb_rd_data_i.addr[31:5], 5'b0};
    assign dcache_wr_addr_o  = stb_rd_data_i.addr;
    assign dcache_wr_data_o  = stb_rd_data_i.data;
    assign dcache_wr_mask_o  = stb_rd_data_i.byte_mask;

endmodule