module inst_aligner (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] raw_data,
    input  logic [ 1:0] pc_low,
    input  logic        valid_in,
    output logic        ready,      // 是否可接收新数据

    output logic [31:0] inst_out,
    output logic        valid_out
);

    logic [31:0] inst_buffer;
    logic        buffer_valid;
    logic        stall;

    // 当需要跨边界但buffer无效时，需停顿
    assign stall = (pc_low == 2'b10) && !buffer_valid && valid_in;
    assign ready = !stall;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_buffer  <= 32'h0;
            buffer_valid <= 1'b0;
            inst_out     <= 32'h0;
            valid_out    <= 1'b0;
        end else begin
            valid_out <= 1'b0;

            if (valid_in && ready) begin
                case (pc_low)
                    2'b00: begin
                        inst_out     <= raw_data;
                        valid_out    <= 1'b1;
                        inst_buffer  <= raw_data;   // 缓存供后续使用
                        buffer_valid <= 1'b1;
                    end
                    2'b10: begin
                        inst_out     <= {raw_data[15:0], inst_buffer[31:16]};
                        valid_out    <= 1'b1;
                        inst_buffer  <= raw_data;
                        buffer_valid <= 1'b1;
                    end
                    default: begin // 非对齐，RISC-V不允许，简单处理
                        inst_out     <= raw_data;
                        valid_out    <= 1'b1;
                        buffer_valid <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule