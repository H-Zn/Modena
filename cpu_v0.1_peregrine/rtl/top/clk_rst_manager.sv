// clk_rst_manager.sv
`timescale 1ns / 1ps

module clk_rst_manager (
    input  logic clk_i,          // 外部时钟
    input  logic rst_n_i,        // 异步复位，低有效

    output logic clk_o,          // 内部时钟（直通或PLL输出，此处直通）
    output logic rst_sync_n_o,   // 同步释放的复位
    output logic pll_locked_o    // PLL锁定指示（若使用MMCM）
);

    // 异步复位同步器（两级触发器）
    logic rst_sync_ff1, rst_sync_ff2;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rst_sync_ff1 <= 1'b0;
            rst_sync_ff2 <= 1'b0;
        end else begin
            rst_sync_ff1 <= 1'b1;
            rst_sync_ff2 <= rst_sync_ff1;
        end
    end

    assign rst_sync_n_o = rst_sync_ff2;
    assign clk_o        = clk_i;      // 直通时钟（实际可接PLL输出）
    assign pll_locked_o = 1'b1;       // 无PLL时默认锁定

endmodule