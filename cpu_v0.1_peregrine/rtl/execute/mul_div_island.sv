// mul_div_island.sv
module mul_div_island (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush_i,

    input  logic        valid_i,         // 指令有效
    input  logic [2:0]  mul_div_op_i,    // funct3
    input  logic [31:0] opa_i,
    input  logic [31:0] opb_i,

    output logic        busy_o,
    output logic [31:0] result_o,
    output logic        result_valid_o
);

    // 乘法（单周期）
    logic [31:0] mul_result;
    logic        mul_sign_a, mul_sign_b;
    logic [63:0] product;

    // 根据 op 决定符号
    assign mul_sign_a = (mul_div_op_i == 3'b010) || (mul_div_op_i == 3'b011); // MULH, MULHSU
    assign mul_sign_b = (mul_div_op_i == 3'b010); // MULH

    // 使用 DSP 风格乘法（综合工具会推断 DSP）
    always_comb begin
        case (mul_div_op_i)
            3'b000: product = $signed(opa_i) * $signed(opb_i);      // MUL
            3'b001: product = $signed(opa_i) * opb_i;               // MULH
            3'b010: product = $signed(opa_i) * $signed(opb_i);      // MULHSU (处理简化)
            3'b011: product = $signed({1'b0, opa_i}) * $signed({1'b0, opb_i}); // MULHU
            default: product = 64'h0;
        endcase
    end
    assign mul_result = (mul_div_op_i == 3'b000) ? product[31:0] : product[63:32];

    // 除法状态机（基-4 SRT 简化模型）
    typedef enum logic [2:0] {IDLE, DIV_CALC, DIV_DONE} div_state_t;
    div_state_t state, next_state;
    logic [31:0] dividend, divisor, quotient, remainder;
    logic [5:0] count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy_o <= 1'b0;
            result_valid_o <= 1'b0;
        end else if (flush_i) begin
            state <= IDLE;
            busy_o <= 1'b0;
            result_valid_o <= 1'b0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (valid_i && (mul_div_op_i == 3'b100 || mul_div_op_i == 3'b101 ||
                                    mul_div_op_i == 3'b110 || mul_div_op_i == 3'b111)) begin
                        // 启动除法
                        dividend <= opa_i;
                        divisor  <= opb_i;
                        quotient <= '0;
                        remainder <= '0;
                        count    <= '0;
                        busy_o   <= 1'b1;
                    end else begin
                        busy_o <= 1'b0;
                    end
                end
                DIV_CALC: begin
                    // 简化的每周期计算（此处仅示意，实际需SRT迭代）
                    // 用组合逻辑计算下一周期商/余数
                    if (count < 32) begin
                        count <= count + 1;
                        // 省略具体迭代逻辑
                    end else begin
                        state <= DIV_DONE;
                    end
                end
                DIV_DONE: begin
                    result_valid_o <= 1'b1;
                    busy_o <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

    // 结果选择
    assign result_o = (mul_div_op_i[2] == 1'b0) ? mul_result : quotient; // 简化

    // 除法忙标志
    always_comb begin
        next_state = state;
        if (state == IDLE && valid_i && mul_div_op_i[2]) next_state = DIV_CALC;
        else if (state == DIV_CALC && count == 32) next_state = DIV_DONE;
        else if (state == DIV_DONE) next_state = IDLE;
    end

endmodule