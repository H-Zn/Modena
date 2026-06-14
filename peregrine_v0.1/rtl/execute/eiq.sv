// eiq.sv
import cpu_pkg::*;

module eiq (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    // 写端口
    input  logic        wr_en_i,
    input  eiq_entry_t  wr_data_i,
    output logic        full_o,

    // 读端口（发射到执行岛）
    input  logic        rd_en_i,         // 头条目发射
    output eiq_entry_t  rd_data_o,
    output logic        empty_o,

    // 操作数就绪监控接口（来自旁路网络/Regfile）
    input  logic        rs1_ready_i,
    input  logic        rs2_ready_i,
    input  logic [31:0] rs1_data_i,
    input  logic [31:0] rs2_data_i,

    // 队列状态
    output logic        stall_req_o
);

    localparam DEPTH = 4;
    eiq_entry_t queue [0:DEPTH-1];
    logic [2:0] wr_ptr, rd_ptr;
    logic [2:0] count;  // 0~4

    assign empty_o = (count == 0);
    assign full_o  = (count == DEPTH);
    assign stall_req_o = full_o;

    // 读数据（头条目）
    assign rd_data_o = queue[rd_ptr];

    // 写指针、读指针、count
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
                eiq_entry_t entry = wr_data_i;
                // 初始操作数未就绪
                entry.rs1_ready = 1'b0;
                entry.rs2_ready = 1'b0;
                entry.rs1_data  = 32'h0;
                entry.rs2_data  = 32'h0;
                queue[wr_ptr] <= entry;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en_i && !empty_o)
                rd_ptr <= rd_ptr + 1'b1;

            if (wr_en_i && !full_o && !(rd_en_i && !empty_o))
                count <= count + 1'b1;
            else if (!(wr_en_i && !full_o) && rd_en_i && !empty_o)
                count <= count - 1'b1;
        end
    end

    // 操作数就绪更新（针对头条目和后续条目）
    // 为简化，此处仅监控头条目。实际设计需遍历队列，但基线按序发射仅需监控头条。
    // 若头条目操作数就绪，则可发射（外部 rd_en_i 由就绪条件生成）。
    // 本模块仅提供数据，就绪判断由外部发射逻辑完成。

endmodule