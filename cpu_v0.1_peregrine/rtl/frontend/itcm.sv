module itcm #(
    parameter SIZE_KB = 4
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] req_addr,
    input  logic        req_valid,
    output logic [31:0] rsp_data,
    output logic        rsp_valid
);

    localparam BASE_ADDR = 32'h0000_0000; // 可配置基地址
    localparam BYTES     = SIZE_KB * 1024;
    localparam DEPTH     = BYTES / 4;

    logic [31:0] mem [0:DEPTH-1];
    logic in_range;
    logic [$clog2(DEPTH)-1:0] word_addr;

    assign in_range  = (req_addr >= BASE_ADDR) && (req_addr < BASE_ADDR + BYTES);
    assign word_addr = req_addr[$clog2(DEPTH)+1:2];

    always_ff @(posedge clk) begin
        if (req_valid && in_range)
            rsp_data <= mem[word_addr];
        else
            rsp_data <= '0;
    end

    assign rsp_valid = req_valid && in_range;

    // 初始化接口 (略，实际需要外部加载)
    // 此处假定由bootloader通过总线写入，或通过$readmemh仿真初始化

endmodule