// uart_tx.sv
// Simple UART Transmitter - 8N1 format
`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,  // 100MHz
    parameter BAUD_RATE = 115200
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic       tx_pin
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;

    state_t state;
    logic [3:0] bit_idx;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [7:0] tx_reg;

    assign tx_ready = (state == IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            bit_idx <= 0;
            clk_cnt <= 0;
            tx_reg  <= 0;
            tx_pin  <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_valid && tx_ready) begin
                        state   <= START;
                        tx_reg  <= tx_data;
                        clk_cnt <= 0;
                    end
                end

                START: begin
                    tx_pin <= 1'b0;  // 起始位
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        state   <= DATA;
                        clk_cnt <= 0;
                        bit_idx <= 0;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                DATA: begin
                    tx_pin <= tx_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        if (bit_idx == 7) begin
                            state <= STOP;
                        end else
                            bit_idx <= bit_idx + 1;
                        clk_cnt <= 0;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                STOP: begin
                    tx_pin <= 1'b1;  // 停止位
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        state <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end

endmodule
