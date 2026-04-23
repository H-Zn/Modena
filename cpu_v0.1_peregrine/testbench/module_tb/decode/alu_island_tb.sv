`timescale 1ns / 1ps
import cpu_pkg::*;

module tb_alu_island;

    logic [3:0]  alu_op;
    logic [31:0] opa, opb;
    logic [31:0] result;

    // 实例化被测模块
    alu_island dut (
        .alu_op_i (alu_op),
        .opa_i    (opa),
        .opb_i    (opb),
        .result_o (result)
    );

    // 黄金模型（软件参考）
    function automatic logic [31:0] ref_alu(logic [3:0] op, logic [31:0] a, logic [31:0] b);
        case (op)
            4'b0000: return a + b;           // ADD
            4'b0001: return a - b;           // SUB
            4'b0010: return a << b[4:0];     // SLL
            4'b0011: return a << b[4:0];     // SLLI (与SLL相同)
            4'b0100: return ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'b0101: return (a < b) ? 32'd1 : 32'd0;                  // SLTU
            4'b0110: return a ^ b;           // XOR
            4'b0111: return a >> b[4:0];     // SRL
            4'b1000: return $signed(a) >>> b[4:0]; // SRA
            4'b1001: return a | b;           // OR
            4'b1010: return a & b;           // AND
            4'b1011: return b;               // LUI (立即数直通)
            4'b1100: return a + b;           // AUIPC (PC+立即数，按加法处理)
            default:  return 32'h0;
        endcase
    endfunction

    int errors = 0;
    int test_num = 0;

    initial begin
        // 定向边界值测试
        $display("[ALU] Directed tests...");
        test_num++;
        alu_op = 4'b0000; opa = 32'h00000000; opb = 32'h00000000; #10;
        check("ADD 0+0");
        alu_op = 4'b0000; opa = 32'hFFFFFFFF; opb = 32'h00000001; #10;
        check("ADD max+1 (overflow)");
        alu_op = 4'b0001; opa = 32'h00000001; opb = 32'h00000001; #10;
        check("SUB 1-1");
        alu_op = 4'b0001; opa = 32'h00000000; opb = 32'h00000001; #10;
        check("SUB 0-1 (negative)");
        alu_op = 4'b0010; opa = 32'h00000001; opb = 32'h00000004; #10;
        check("SLL 1<<4");
        alu_op = 4'b0100; opa = 32'h80000000; opb = 32'h00000000; #10;
        check("SLT -2147483648 < 0");
        alu_op = 4'b0101; opa = 32'hFFFFFFFF; opb = 32'h00000001; #10;
        check("SLTU max > 1");
        alu_op = 4'b1000; opa = 32'h80000000; opb = 32'h00000001; #10;
        check("SRA sign extend");
        alu_op = 4'b1011; opa = 32'h00000000; opb = 32'h12345678; #10;
        check("LUI pass through");

        // 随机测试
        $display("[ALU] Random tests (1000 vectors)...");
        for (int i = 0; i < 1000; i++) begin
            alu_op = $urandom_range(0, 12);
            opa   = $urandom();
            opb   = $urandom();
            #10;
            check($sformatf("Random %0d", i));
        end

        // 总结
        $display("=================================");
        if (errors == 0) $display("ALU ALL TESTS PASSED!");
        else $display("ALU TEST FAILED with %0d errors.", errors);
        $display("=================================");
        $finish;
    end

    task automatic check(string msg);
        automatic logic [31:0] exp = ref_alu(alu_op, opa, opb);
        if (result !== exp) begin
            $error("[%s] ALU mismatch: op=%b, opa=%h, opb=%h, got=%h, exp=%h",
                   msg, alu_op, opa, opb, result, exp);
            errors++;
        end
    endtask

endmodule