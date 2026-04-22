// bru_island.sv
module bru_island (
    input  logic [2:0]  branch_type_i,
    input  logic [31:0] opa_i,
    input  logic [31:0] opb_i,
    input  logic [31:0] pc_i,
    input  logic [31:0] imm_i,
    input  logic        pred_dir_i,     // 感知器预测方向

    output logic        flush_o,
    output logic [31:0] flush_target_o,
    output logic        actual_taken_o,
    output logic        mispredict_o
);

    // 条件判断
    logic cond_true;
    always_comb begin
        case (branch_type_i)
            3'b000: cond_true = (opa_i == opb_i);           // BEQ
            3'b001: cond_true = (opa_i != opb_i);           // BNE
            3'b010: cond_true = ($signed(opa_i) < $signed(opb_i));   // BLT
            3'b011: cond_true = ($signed(opa_i) >= $signed(opb_i));  // BGE
            3'b100: cond_true = (opa_i < opb_i);            // BLTU
            3'b101: cond_true = (opa_i >= opb_i);           // BGEU
            default: cond_true = 1'b0;
        endcase
    end

    assign actual_taken_o = cond_true;
    assign mispredict_o   = (pred_dir_i != actual_taken_o);

    // 目标地址（分支：pc+imm；跳转目标由外部传入，此处简化）
    logic [31:0] target_pc;
    assign target_pc = pc_i + imm_i;

    assign flush_o       = mispredict_o;
    assign flush_target_o = actual_taken_o ? target_pc : (pc_i + 32'd4);

endmodule