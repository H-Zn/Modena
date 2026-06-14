// maq.sv
`timescale 1ns / 1ps
import cpu_pkg::*;

module maq (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,         // 冲刷信号

    // 写端口（来自 dae_splitter）
    input  logic        wr_en_i,
    input  maq_entry_t  wr_data_i,
    output logic        full_o,

    // 读端口（送往 AGU / EX1）
    input  logic        rd_en_i,         // 读使能，弹出头条目
    output maq_entry_t  rd_data_o,
    output logic        empty_o,

    // 停顿反馈（满时反压 ID）
    output logic        stall_req_o
);

    localparam DEPTH = 2;
    maq_entry_t queue [0:DEPTH-1];
    logic [1:0] wr_ptr, rd_ptr;
    logic [1:0] count;  // 0~2

    assign empty_o = (count == 0);
    assign full_o  = (count == DEPTH);
    assign stall_req_o = full_o;

    // 读数据
    assign rd_data_o = queue[rd_ptr];

    // 写指针和读指针更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else if (flush_i) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (wr_en_i && !full_o) begin
                queue[wr_ptr] <= wr_data_i;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en_i && !empty_o) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            // count 更新
            if (wr_en_i && !full_o && !(rd_en_i && !empty_o))
                count <= count + 1'b1;
            else if (!(wr_en_i && !full_o) && rd_en_i && !empty_o)
                count <= count - 1'b1;
        end
    end

endmodule