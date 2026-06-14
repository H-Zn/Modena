// decoder.sv
`timescale 1ns / 1ps
import cpu_pkg::*;

module decoder (
    input  logic [31:0] inst_i,
    input  logic [31:0] pc_i,
    output micro_op_t    micro_op_o,
    output logic         illegal_o
);

    // 局部信号
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs1, rs2, rd;
    logic [11:0] csr_addr;
    logic [31:0] imm;

    // 字段提取
    assign opcode   = inst_i[6:0];
    assign funct3   = inst_i[14:12];
    assign funct7   = inst_i[31:25];
    assign rs1      = inst_i[19:15];
    assign rs2      = inst_i[24:20];
    assign rd       = inst_i[11:7];
    assign csr_addr = inst_i[31:20];

    // 立即数生成 (支持所有格式)
    always_comb begin
        case (opcode)
            // I-type: LB, LH, LW, LBU, LHU, ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI, JALR, CSR*, ECALL/EBREAK, WFI
            7'b0000011, 7'b0010011, 7'b1100111, 7'b1110011:
                imm = {{20{inst_i[31]}}, inst_i[31:20]};
            // S-type: SB, SH, SW, SC (A扩展)
            7'b0100011:
                imm = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
            // B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
            7'b1100011:
                imm = {{19{inst_i[31]}}, inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
            // U-type: LUI, AUIPC
            7'b0110111, 7'b0010111:
                imm = {inst_i[31:12], 12'b0};
            // J-type: JAL
            7'b1101111:
                imm = {{11{inst_i[31]}}, inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
            // R-type: ALU, MUL/DIV/REM, Atomic (部分)
            7'b0110011, 7'b0111011, 7'b0101111:
                imm = 32'h0;
            default: imm = 32'h0;
        endcase
    end

    // 控制信号生成
    always_comb begin
        // 默认值
        micro_op_o = '0;
        micro_op_o.opcode   = opcode;
        micro_op_o.funct3   = funct3;
        micro_op_o.funct7   = funct7;
        micro_op_o.csr_addr = csr_addr;
        micro_op_o.rs1_addr = rs1;
        micro_op_o.rs2_addr = rs2;
        micro_op_o.rd_addr  = rd;
        micro_op_o.imm      = imm;
        illegal_o = 1'b0;

        // 操作数使用标志
        micro_op_o.rs1_used = (opcode != 7'b0110111) && (opcode != 7'b0010111) && (opcode != 7'b1101111);
        micro_op_o.rs2_used = (opcode == 7'b0110011) || (opcode == 7'b0100011) || (opcode == 7'b1100011) ||
                              (opcode == 7'b0111011) || (opcode == 7'b0101111);
        micro_op_o.rd_wen   = (opcode == 7'b0110111) || (opcode == 7'b0010111) || (opcode == 7'b1101111) ||
                              (opcode == 7'b1100111) || (opcode == 7'b0000011) || (opcode == 7'b0010011) ||
                              (opcode == 7'b0110011) || (opcode == 7'b0111011) ||
                              ((opcode == 7'b1110011) && (funct3 != 3'b000)) || // CSR
                              ((opcode == 7'b0101111) && (funct3[2] == 1'b0));   // LR/AMO* 有rd写回

        // 立即数选择
        micro_op_o.alu_src1_sel = (opcode == 7'b0010111) || (opcode == 7'b1101111) || (opcode == 7'b1100111); // AUIPC, JAL, JALR 使用PC
        micro_op_o.alu_src2_sel = (opcode != 7'b0110011) && (opcode != 7'b0111011) && (opcode != 7'b0101111);

        case (opcode)
            // ----- Load -----
            7'b0000011: begin
                micro_op_o.mem_read = 1'b1;
                micro_op_o.alu_op   = 4'b0000; // ADD
                case (funct3)
                    3'b000:  begin micro_op_o.mem_width = 2'b00; micro_op_o.mem_sign_ext = 1'b1; end
                    3'b001:  begin micro_op_o.mem_width = 2'b01; micro_op_o.mem_sign_ext = 1'b1; end
                    3'b010:  begin micro_op_o.mem_width = 2'b10; micro_op_o.mem_sign_ext = 1'b0; end
                    3'b100:  begin micro_op_o.mem_width = 2'b00; micro_op_o.mem_sign_ext = 1'b0; end
                    3'b101:  begin micro_op_o.mem_width = 2'b01; micro_op_o.mem_sign_ext = 1'b0; end
                    default: illegal_o = 1'b1;
                endcase
            end

            // ----- Store -----
            7'b0100011: begin
                micro_op_o.mem_write = 1'b1;
                micro_op_o.alu_op    = 4'b0000;
                case (funct3)
                    3'b000: micro_op_o.mem_width = 2'b00;
                    3'b001: micro_op_o.mem_width = 2'b01;
                    3'b010: micro_op_o.mem_width = 2'b10;
                    default: illegal_o = 1'b1;
                endcase
            end

            // ----- Atomic (A扩展) -----
            7'b0101111: begin
                micro_op_o.is_atomic = 1'b1;
                micro_op_o.mem_aq    = funct3[1];
                micro_op_o.mem_rl    = funct3[2];
                micro_op_o.atomic_op = {funct7[6:2], funct3[0]};
                case (funct3[1:0])
                    2'b00: micro_op_o.mem_width = 2'b10; // word
                    2'b01: micro_op_o.mem_width = 2'b10;
                    2'b10: micro_op_o.mem_width = 2'b10;
                    default: illegal_o = 1'b1;
                endcase
                // 根据funct5区分具体原子操作
                if (funct7[6:2] == 5'b00010) micro_op_o.alu_op = 4'b0000; // LR/SC (地址计算)
                else micro_op_o.alu_op = 4'b0000; // AMO (地址计算)
            end

            // ----- Branch -----
            7'b1100011: begin
                micro_op_o.is_branch = 1'b1;
                case (funct3)
                    3'b000: micro_op_o.branch_type = 3'b000; // BEQ
                    3'b001: micro_op_o.branch_type = 3'b001; // BNE
                    3'b100: micro_op_o.branch_type = 3'b010; // BLT
                    3'b101: micro_op_o.branch_type = 3'b011; // BGE
                    3'b110: micro_op_o.branch_type = 3'b100; // BLTU
                    3'b111: micro_op_o.branch_type = 3'b101; // BGEU
                    default: illegal_o = 1'b1;
                endcase
            end

            // ----- JAL -----
            7'b1101111: begin
                micro_op_o.is_jal = 1'b1;
                micro_op_o.alu_op = 4'b1111; // ADD (PC+4)
                micro_op_o.is_call = (rd == 5'd1) || (rd == 5'd5);
            end

            // ----- JALR -----
            7'b1100111: begin
                micro_op_o.is_jalr = 1'b1;
                micro_op_o.alu_op  = 4'b0000; // ADD
                micro_op_o.is_ret  = (rs1 == 5'd1) || (rs1 == 5'd5);
                if (funct3 != 3'b000) illegal_o = 1'b1;
            end

            // ----- ALU immediate -----
            7'b0010011: begin
                case (funct3)
                    3'b000: micro_op_o.alu_op = 4'b0000; // ADDI
                    3'b001: micro_op_o.alu_op = (funct7[5] ? 4'b0011 : 4'b0010); // SLLI
                    3'b010: micro_op_o.alu_op = 4'b0100; // SLTI
                    3'b011: micro_op_o.alu_op = 4'b0101; // SLTIU
                    3'b100: micro_op_o.alu_op = 4'b0110; // XORI
                    3'b101: micro_op_o.alu_op = (funct7[5] ? 4'b1000 : 4'b0111); // SRLI/SRAI
                    3'b110: micro_op_o.alu_op = 4'b1001; // ORI
                    3'b111: micro_op_o.alu_op = 4'b1010; // ANDI
                    default: illegal_o = 1'b1;
                endcase
            end

            // ----- ALU register -----
            7'b0110011: begin
                case (funct3)
                    3'b000: micro_op_o.alu_op = (funct7[5] ? 4'b0001 : 4'b0000); // SUB/ADD
                    3'b001: micro_op_o.alu_op = 4'b0010; // SLL
                    3'b010: micro_op_o.alu_op = 4'b0100; // SLT
                    3'b011: micro_op_o.alu_op = 4'b0101; // SLTU
                    3'b100: micro_op_o.alu_op = 4'b0110; // XOR
                    3'b101: micro_op_o.alu_op = (funct7[5] ? 4'b1000 : 4'b0111); // SRA/SRL
                    3'b110: micro_op_o.alu_op = 4'b1001; // OR
                    3'b111: micro_op_o.alu_op = 4'b1010; // AND
                    default: illegal_o = 1'b1;
                endcase
            end

            // ----- M扩展 (乘除法) -----
            7'b0111011: begin
                micro_op_o.is_mul_div = 1'b1;
                micro_op_o.mul_div_op = funct3;
                if (funct7 != 7'b0000001) illegal_o = 1'b1;
            end

            // ----- LUI -----
            7'b0110111: begin
                micro_op_o.alu_op = 4'b1011; // LUI
            end

            // ----- AUIPC -----
            7'b0010111: begin
                micro_op_o.alu_op = 4'b1100; // AUIPC
            end

            // ----- SYSTEM -----
            7'b1110011: begin
                case (funct3)
                    3'b000: begin
                        case (csr_addr)
                            12'h000: micro_op_o.is_ecall  = 1'b1;
                            12'h001: micro_op_o.is_ebreak = 1'b1;
                            12'h302: micro_op_o.is_mret   = 1'b1;
                            12'h102: micro_op_o.is_sret   = 1'b1;
                            12'h105: micro_op_o.is_wfi    = 1'b1;
                            default: illegal_o = 1'b1;
                        endcase
                    end
                    3'b001, 3'b010, 3'b011, 3'b101, 3'b110, 3'b111: begin
                        micro_op_o.is_csr = 1'b1;
                        micro_op_o.csr_op = funct3[1:0];
                        // CSR地址已在csr_addr中
                    end
                    default: illegal_o = 1'b1;
                endcase
            end

            // ----- FENCE / FENCE.I -----
            7'b0001111: begin
                micro_op_o.is_fence = 1'b1;
                if (funct3 == 3'b001) begin // FENCE.I
                    // 产生冲刷请求，由外部处理
                end
            end

            default: illegal_o = 1'b1;
        endcase

        // 非法指令检测补充：寄存器x0写使能禁止
        if (micro_op_o.rd_wen && rd == 5'd0)
            micro_op_o.rd_wen = 1'b0;
    end

endmodule