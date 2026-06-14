// tcm.sv
import cpu_pkg::*;

module tcm #(
    parameter SIZE_KB = 4,
    parameter BASE_ADDR = 32'h8000_0000
) (
    input  logic        clk,
    input  logic        rst_n,

    // 访存请求
    input  logic        req_valid_i,
    input  mem_req_type_t req_type_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [ 3:0] req_wmask_i,

    // 响应
    output logic        rsp_valid_o,
    output logic [31:0] rsp_rdata_o,

    // 初始化接口 (可选)
    input  logic        init_wr_en_i,
    input  logic [31:0] init_addr_i,
    input  logic [31:0] init_data_i
);

    localparam BYTES = SIZE_KB * 1024;
    localparam DEPTH = BYTES / 4;
    localparam ADDR_WIDTH = $clog2(DEPTH) + 2;

    logic [31:0] mem [0:DEPTH-1];
    logic in_range;
    logic [ADDR_WIDTH-1:0] word_addr;

    assign in_range  = (req_addr_i >= BASE_ADDR) && (req_addr_i < BASE_ADDR + BYTES);
    assign word_addr = req_addr_i[ADDR_WIDTH-1:2];

    // 读操作 (组合逻辑，单周期)
    always_comb begin
        rsp_rdata_o = 32'h0;
        if (req_valid_i && in_range && req_type_i == MEM_REQ_LOAD)
            rsp_rdata_o = mem[word_addr];
    end

    assign rsp_valid_o = req_valid_i && in_range;

    // 写操作 (时序)
    always_ff @(posedge clk) begin
        if (init_wr_en_i)
            mem[init_addr_i[ADDR_WIDTH-1:2]] <= init_data_i;
        else if (req_valid_i && in_range && req_type_i == MEM_REQ_STORE) begin
            // 根据字节掩码写
            for (int i = 0; i < 4; i++) begin
                if (req_wmask_i[i])
                    mem[word_addr][8*i +: 8] <= req_wdata_i[8*i +: 8];
            end
        end
    end

endmodule