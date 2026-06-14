// agu.sv
module agu (
    input  logic [31:0] base_i,       // 基址值 (rs1 或前递数据)
    input  logic [31:0] offset_i,     // 立即数偏移
    output logic [31:0] addr_o,
    output logic        misaligned_o  // 地址未对齐标志（根据访存宽度判断）
);

    assign addr_o = base_i + offset_i;

    // 地址对齐检查（此处仅提供组合输出，实际需结合 mem_width）
    // 由外部调用时结合 mem_width 判断
    assign misaligned_o = 1'b0; // 具体逻辑在外部根据 mem_width 实现

endmodule