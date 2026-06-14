// dcache.sv
// Data Cache - 4-way set-associative, write-back with MSHR
`timescale 1ns / 1ps
import cpu_pkg::*;

module dcache #(
    parameter CACHE_SIZE   = 16*1024,
    parameter LINE_SIZE    = 32,
    parameter WAYS         = 4
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    input  logic        req_valid_i,
    input  mem_req_type_t req_type_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [ 3:0] req_wmask_i,
    input  logic        req_is_atomic_i,
    input  logic [ 3:0] req_atomic_op_i,

    output logic        rsp_valid_o,
    output logic [31:0] rsp_rdata_o,
    output logic        rsp_miss_o,

    output logic        mshr_alloc_valid_o,
    output logic [31:0] mshr_alloc_addr_o,
    output logic        mshr_alloc_is_write_o,
    input  logic        mshr_alloc_ready_i,
    input  logic [ 1:0] mshr_alloc_id_i,

    input  logic        mshr_fill_valid_i,
    input  logic [ 1:0] mshr_fill_id_i,
    input  logic [31:0] mshr_fill_addr_i,
    input  logic [31:0] mshr_fill_data_i,
    input  logic        mshr_fill_last_i,

    output logic        wb_req_valid_o,
    output logic [31:0] wb_req_addr_o,
    output logic [31:0] wb_req_data_o,
    output logic [ 3:0] wb_req_mask_o,
    input  logic        wb_req_ready_i
);

    localparam NUM_SETS    = CACHE_SIZE / (LINE_SIZE * WAYS);
    localparam INDEX_BITS  = $clog2(NUM_SETS);
    localparam OFFSET_BITS = $clog2(LINE_SIZE);
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;
    localparam WORDS_PER_LINE = LINE_SIZE / 4;

    typedef enum logic [2:0] {
        D_IDLE,
        D_LOOKUP,
        D_REFILL,
        D_WRITEBACK,
        D_WRITE_ALLOCATE
    } dcache_state_t;

    dcache_state_t state, next_state;

    typedef struct packed {
        logic [TAG_BITS-1:0] tag;
        logic                valid;
        logic                dirty;
    } tag_entry_t;

    tag_entry_t tag_ram [0:NUM_SETS-1][0:WAYS-1];
    logic [31:0] data_ram [0:NUM_SETS-1][0:WAYS-1][0:WORDS_PER_LINE-1];
    logic [1:0] plru [0:NUM_SETS-1];

    logic [TAG_BITS-1:0] req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    logic [OFFSET_BITS-1:0] req_offset;
    logic [$clog2(WORDS_PER_LINE)-1:0] req_word;

    assign req_tag    = req_addr_i[31:INDEX_BITS+OFFSET_BITS];
    assign req_idx    = req_addr_i[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    assign req_offset = req_addr_i[OFFSET_BITS-1:0];
    assign req_word   = req_offset[OFFSET_BITS-1:2];

    logic hit;
    logic [1:0] hit_way;
    logic [$clog2(WORDS_PER_LINE)-1:0] hit_word;

    always_comb begin
        hit      = 1'b0;
        hit_way  = 2'b00;
        for (int w = 0; w < WAYS; w++) begin
            if (tag_ram[req_idx][w].valid && tag_ram[req_idx][w].tag == req_tag) begin
                hit     = 1'b1;
                hit_way = w[1:0];
            end
        end
    end

    assign hit_word  = req_word;
    assign rsp_rdata_o = (state == D_LOOKUP && hit) ?
                         data_ram[req_idx][hit_way][hit_word] : 32'h0;
    assign rsp_valid_o = (state == D_LOOKUP) && hit;
    assign rsp_miss_o  = (state == D_LOOKUP) && !hit && req_valid_i;

    logic [1:0] victim_way;
    assign victim_way = plru[req_idx][1] ?
                        (plru[req_idx][0] ? 2'b11 : 2'b10) :
                        (plru[req_idx][0] ? 2'b01 : 2'b00);

    logic [$clog2(DEPTH)-1:0] fill_ptr;
    logic [$clog2(DEPTH)-1:0] wb_ptr;
    logic [$clog2(WORDS_PER_LINE)-1:0] wb_word_cnt;

    typedef struct packed {
        logic valid;
        logic [$clog2(NUM_SETS)-1:0] idx;
        logic [TAG_BITS-1:0] tag;
        logic [1:0] way;
        logic [31:0] data [0:WORDS_PER_LINE-1];
        logic dirty;
    } pending_fill_t;

    pending_fill_t pending_fill;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= D_IDLE;
            pending_fill <= '0;
            wb_word_cnt <= '0;
            for (int s = 0; s < NUM_SETS; s++) begin
                plru[s] <= 2'b00;
                for (int w = 0; w < WAYS; w++) begin
                    tag_ram[s][w] <= '0;
                    for (int ww = 0; ww < WORDS_PER_LINE; ww++)
                        data_ram[s][w][ww] <= 32'h0;
                end
            end
        end else if (flush_i) begin
            state <= D_IDLE;
        end else begin
            case (state)
                D_IDLE: begin
                    if (req_valid_i)
                        state <= D_LOOKUP;
                end

                D_LOOKUP: begin
                    if (hit) begin
                        if (req_type_i == MEM_REQ_STORE) begin
                            data_ram[req_idx][hit_way][hit_word] <= req_wdata_i;
                            for (int b = 0; b < 4; b++) begin
                                if (req_wmask_i[b])
                                    data_ram[req_idx][hit_way][hit_word][b*8 +: 8] <= req_wdata_i[b*8 +: 8];
                            end
                            tag_ram[req_idx][hit_way].dirty <= 1'b1;
                        end
                        state <= D_IDLE;
                    end else begin
                        if (tag_ram[req_idx][victim_way].valid && tag_ram[req_idx][victim_way].dirty) begin
                            state <= D_WRITEBACK;
                            wb_word_cnt <= '0;
                        end else begin
                            if (mshr_alloc_ready_i) begin
                                state <= D_REFILL;
                                pending_fill.valid <= 1'b1;
                                pending_fill.idx   <= req_idx;
                                pending_fill.tag   <= req_tag;
                                pending_fill.way   <= victim_way;
                                pending_fill.dirty <= (req_type_i == MEM_REQ_STORE);
                                for (int ww = 0; ww < WORDS_PER_LINE; ww++)
                                    pending_fill.data[ww] <= 32'h0;
                            end
                        end
                    end
                end

                D_WRITEBACK: begin
                    if (wb_req_ready_i) begin
                        wb_word_cnt <= wb_word_cnt + 1'b1;
                        if (wb_word_cnt == WORDS_PER_LINE - 1) begin
                            tag_ram[req_idx][victim_way].dirty <= 1'b0;
                            if (mshr_alloc_ready_i) begin
                                state <= D_REFILL;
                                pending_fill.valid <= 1'b1;
                                pending_fill.idx   <= req_idx;
                                pending_fill.tag   <= req_tag;
                                pending_fill.way   <= victim_way;
                                pending_fill.dirty <= (req_type_i == MEM_REQ_STORE);
                            end else begin
                                state <= D_IDLE;
                            end
                        end
                    end
                end

                D_REFILL: begin
                    if (mshr_fill_valid_i) begin
                        for (int ww = 0; ww < WORDS_PER_LINE; ww++) begin
                            if (mshr_fill_addr_i[OFFSET_BITS-1:2] == ww[$clog2(WORDS_PER_LINE)-1:0])
                                pending_fill.data[ww] <= mshr_fill_data_i;
                        end
                        if (mshr_fill_last_i) begin
                            tag_ram[pending_fill.idx][pending_fill.way].tag   <= pending_fill.tag;
                            tag_ram[pending_fill.idx][pending_fill.way].valid <= 1'b1;
                            tag_ram[pending_fill.idx][pending_fill.way].dirty <= pending_fill.dirty;
                            for (int ww = 0; ww < WORDS_PER_LINE; ww++)
                                data_ram[pending_fill.idx][pending_fill.way][ww] <= pending_fill.data[ww];

                            plru[pending_fill.idx] <= ~pending_fill.way;
                            pending_fill.valid <= 1'b0;
                            state <= D_LOOKUP;
                        end
                    end
                end

                default: state <= D_IDLE;
            endcase
        end
    end

    assign mshr_alloc_valid_o    = (state == D_LOOKUP) && !hit && req_valid_i;
    assign mshr_alloc_addr_o     = {req_addr_i[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    assign mshr_alloc_is_write_o = (req_type_i == MEM_REQ_STORE);

    assign wb_req_valid_o = (state == D_WRITEBACK);
    assign wb_req_addr_o  = {tag_ram[req_idx][victim_way].tag, req_idx, {OFFSET_BITS{1'b0}}}
                            + {27'b0, wb_word_cnt, 2'b00};
    assign wb_req_data_o  = data_ram[req_idx][victim_way][wb_word_cnt];
    assign wb_req_mask_o  = 4'hF;

endmodule
