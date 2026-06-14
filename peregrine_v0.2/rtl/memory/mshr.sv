// mshr.sv
// Miss Status Holding Register - tracks outstanding cache misses
`timescale 1ns / 1ps
import cpu_pkg::*;

module mshr #(
    parameter NUM_ENTRIES = 4
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    input  logic        alloc_valid_i,
    input  logic [31:0] alloc_addr_i,
    input  logic        alloc_is_write_i,
    output logic        alloc_ready_o,
    output logic [1:0]  alloc_id_o,

    output logic        fill_req_valid_o,
    output logic [31:0] fill_req_addr_o,
    output logic        fill_req_is_write_o,
    input  logic        fill_req_ready_i,

    input  logic        fill_data_valid_i,
    input  logic [31:0] fill_data_i,
    input  logic        fill_data_last_i,

    output logic        fill_done_valid_o,
    output logic [1:0]  fill_done_id_o
);

    typedef enum logic [1:0] {
        M_FREE,
        M_PENDING,
        M_FILLING,
        M_DONE
    } mshr_state_t;

    typedef struct packed {
        logic              valid;
        mshr_state_t       state;
        logic [31:0]       line_addr;
        logic              is_write;
        logic [$clog2(NUM_ENTRIES)-1:0] id;
    } mshr_entry_t;

    mshr_entry_t entries [0:NUM_ENTRIES-1];
    logic [$clog2(NUM_ENTRIES)-1:0] alloc_ptr;
    logic [$clog2(NUM_ENTRIES)-1:0] serve_ptr;

    logic any_free;
    logic [$clog2(NUM_ENTRIES)-1:0] free_idx;

    always_comb begin
        any_free = 1'b0;
        free_idx = '0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (!entries[i].valid && !any_free) begin
                any_free = 1'b1;
                free_idx = i[$clog2(NUM_ENTRIES)-1:0];
            end
        end
    end

    assign alloc_ready_o = any_free;
    assign alloc_id_o    = free_idx;

    logic serve_valid;
    logic [$clog2(NUM_ENTRIES)-1:0] serve_idx;

    always_comb begin
        serve_valid = 1'b0;
        serve_idx   = '0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entries[i].valid && entries[i].state == M_PENDING && !serve_valid) begin
                serve_valid = 1'b1;
                serve_idx   = i[$clog2(NUM_ENTRIES)-1:0];
            end
        end
    end

    assign fill_req_valid_o   = serve_valid;
    assign fill_req_addr_o    = entries[serve_idx].line_addr;
    assign fill_req_is_write_o = entries[serve_idx].is_write;

    logic fill_done_valid;
    logic [$clog2(NUM_ENTRIES)-1:0] fill_done_idx;

    always_comb begin
        fill_done_valid = 1'b0;
        fill_done_idx   = '0;
        for (int i = 0; i < NUM_ENTRIES; i++) begin
            if (entries[i].valid && entries[i].state == M_FILLING && !fill_done_valid) begin
                fill_done_valid = 1'b1;
                fill_done_idx   = i[$clog2(NUM_ENTRIES)-1:0];
            end
        end
    end

    assign fill_done_valid_o = fill_data_valid_i && fill_data_last_i;
    assign fill_done_id_o    = fill_done_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                entries[i] <= '0;
            end
            alloc_ptr <= '0;
            serve_ptr <= '0;
        end else if (flush_i) begin
            for (int i = 0; i < NUM_ENTRIES; i++) begin
                entries[i].valid <= 1'b0;
                entries[i].state <= M_FREE;
            end
        end else begin
            if (alloc_valid_i && alloc_ready_o) begin
                entries[free_idx].valid     <= 1'b1;
                entries[free_idx].state     <= M_PENDING;
                entries[free_idx].line_addr <= alloc_addr_i;
                entries[free_idx].is_write  <= alloc_is_write_i;
                entries[free_idx].id        <= free_idx;
            end

            if (fill_req_valid_o && fill_req_ready_i) begin
                entries[serve_idx].state <= M_FILLING;
            end

            if (fill_data_valid_i && fill_data_last_i) begin
                entries[fill_done_idx].valid <= 1'b0;
                entries[fill_done_idx].state <= M_DONE;
            end
        end
    end

endmodule
