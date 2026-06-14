// srb.sv
// Shared Result Buffer - In-Order Commit
`timescale 1ns / 1ps
import cpu_pkg::*;

module srb #(
    parameter DEPTH = 16
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    input  logic        alloc_en_i,
    input  logic [ 4:0] alloc_rd_addr_i,
    input  logic        alloc_rd_wen_i,
    input  logic [31:0] alloc_pc_i,
    output logic [ 4:0] alloc_idx_o,
    output logic        alloc_full_o,

    input  logic        result_wr_en_i,
    input  logic [ 4:0] result_idx_i,
    input  logic [31:0] result_data_i,
    input  logic        result_exception_i,
    input  exc_code_t   result_exc_code_i,

    output logic        commit_valid_o,
    output logic [ 4:0] commit_rd_addr_o,
    output logic [31:0] commit_rd_data_o,
    output logic        commit_rd_wen_o,

    output logic        store_commit_o,
    output logic [ 2:0] store_commit_idx_o,

    output logic        exc_req_o,
    output logic [31:0] exc_pc_o,
    output exc_code_t   exc_code_o,

    output logic        stall_wb_o,
    output logic        instret_event_o
);

    srb_entry_t buffer [0:DEPTH-1];
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] rd_ptr;
    logic [$clog2(DEPTH):0]   count;

    assign alloc_idx_o  = wr_ptr;
    assign alloc_full_o = (count == DEPTH);

    logic head_ready;
    assign head_ready = buffer[rd_ptr].valid && buffer[rd_ptr].ready && !buffer[rd_ptr].exception;
    assign stall_wb_o = (count > 0) && !head_ready && !flush_i;

    assign commit_valid_o   = head_ready && !flush_i;
    assign commit_rd_addr_o = buffer[rd_ptr].rd_addr;
    assign commit_rd_data_o = buffer[rd_ptr].result;
    assign commit_rd_wen_o  = buffer[rd_ptr].rd_wen;

    assign store_commit_o    = commit_valid_o && !buffer[rd_ptr].rd_wen;
    assign store_commit_idx_o = rd_ptr[2:0];

    assign exc_req_o  = (count > 0) && buffer[rd_ptr].valid && buffer[rd_ptr].exception && !flush_i;
    assign exc_pc_o   = buffer[rd_ptr].pc;
    assign exc_code_o = buffer[rd_ptr].exc_code;

    assign instret_event_o = commit_valid_o;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                buffer[i] <= '0;
            end
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else if (flush_i) begin
            for (int i = 0; i < DEPTH; i++) begin
                buffer[i].valid <= 1'b0;
            end
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (alloc_en_i && !alloc_full_o) begin
                buffer[wr_ptr].valid    <= 1'b1;
                buffer[wr_ptr].ready    <= 1'b0;
                buffer[wr_ptr].rd_addr  <= alloc_rd_addr_i;
                buffer[wr_ptr].rd_wen   <= alloc_rd_wen_i;
                buffer[wr_ptr].pc       <= alloc_pc_i;
                buffer[wr_ptr].result   <= 32'h0;
                buffer[wr_ptr].exception<= 1'b0;
                buffer[wr_ptr].exc_code <= exc_code_t'(0);
                wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
            end

            if (result_wr_en_i && result_idx_i < DEPTH) begin
                buffer[result_idx_i].result    <= result_data_i;
                buffer[result_idx_i].ready     <= 1'b1;
                buffer[result_idx_i].exception <= result_exception_i;
                buffer[result_idx_i].exc_code  <= result_exc_code_i;
            end

            if (commit_valid_o) begin
                buffer[rd_ptr].valid <= 1'b0;
                rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
            end

            if (alloc_en_i && !alloc_full_o && !commit_valid_o)
                count <= count + 1'b1;
            else if (!(alloc_en_i && !alloc_full_o) && commit_valid_o)
                count <= count - 1'b1;
        end
    end

endmodule
