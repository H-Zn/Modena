// alu_island.sv
//
`timescale 1ns / 1ps

module alu_island (
    input  logic [3:0]  alu_op_i,
    input  logic [31:0] opa_i,
    input  logic [31:0] opb_i,
    output logic [31:0] result_o
);

    always_comb begin
        case (alu_op_i)
            4'b0000: result_o = opa_i + opb_i;           // ADD
            4'b0001: result_o = opa_i - opb_i;           // SUB
            4'b0010: result_o = opa_i << opb_i[4:0];     // SLL
            4'b0011: result_o = opa_i << opb_i[4:0];     // SLLI (same)
            4'b0100: result_o = ($signed(opa_i) < $signed(opb_i)) ? 32'd1 : 32'd0; // SLT
            4'b0101: result_o = (opa_i < opb_i) ? 32'd1 : 32'd0;                  // SLTU
            4'b0110: result_o = opa_i ^ opb_i;           // XOR
            4'b0111: result_o = opa_i >> opb_i[4:0];     // SRL
            4'b1000: result_o = $signed(opa_i) >>> opb_i[4:0]; // SRA
            4'b1001: result_o = opa_i | opb_i;           // OR
            4'b1010: result_o = opa_i & opb_i;           // AND
            4'b1011: result_o = opb_i;                   // LUI (imm)
            4'b1100: result_o = opa_i + opb_i;           // AUIPC (pc+imm)
            default: result_o = 32'h0;
        endcase
    end

endmodule
