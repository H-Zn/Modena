import cpu_pkg::*;

module tb_bypass_network;

    logic [4:0]  rs1_addr, rs2_addr;
    logic [31:0] rf_rs1, rf_rs2;

    // 旁路源
    logic [4:0]  ex2_rd, mem_rd, wb_rd;
    logic        ex2_wen, mem_wen, wb_wen;
    logic [31:0] ex2_result, mem_result, wb_result;

    // 输出
    logic [31:0] op1, op2;

    bypass_network dut (
        .rs1_addr_i   (rs1_addr),
        .rs2_addr_i   (rs2_addr),
        .rf_rs1_data_i(rf_rs1),
        .rf_rs2_data_i(rf_rs2),
        .ex2_rd_i     (ex2_rd),
        .ex2_wen_i    (ex2_wen),
        .ex2_result_i (ex2_result),
        .mem_rd_i     (mem_rd),
        .mem_wen_i    (mem_wen),
        .mem_result_i (mem_result),
        .wb_rd_i      (wb_rd),
        .wb_wen_i     (wb_wen),
        .wb_result_i  (wb_result),
        .op1_o        (op1),
        .op2_o        (op2)
    );

    int errors = 0;

    function automatic logic [31:0] expected_val(
        int rs_used, int rs_addr,
        int ex2_rd_, int ex2_wen_, int ex2_res,
        int mem_rd_, int mem_wen_, int mem_res,
        int wb_rd_, int wb_wen_, int wb_res,
        int rf_val
    );
        if (rs_addr == 0) return 0;
        if (ex2_wen_ && ex2_rd_ == rs_addr) return ex2_res;
        else if (mem_wen_ && mem_rd_ == rs_addr) return mem_res;
        else if (wb_wen_ && wb_rd_ == rs_addr) return wb_res;
        else return rf_val;
    endfunction

    // 简化的测试场景枚举
    initial begin
        $display("[Bypass] Testing bypass priorities...");
        // 无旁路
        set_state(1,1, 100,200, 0,0,0, 0,0,0, 0,0,0);
        #10;
        check("RF only", op1==100, op2==200);

        // EX2旁路
        set_state(1,1, 100,200, 1,1,333, 0,0,0, 0,0,0);
        #10;
        check("EX2 bypass rs1", op1==333, op2==333);

        // EX2 vs MEM 优先级 (EX2 最新)
        set_state(1,1, 100,200, 1,1,111, 1,1,222, 0,0,0);
        #10;
        check("EX2 > MEM", op1==111, op2==111);

        // MEM vs WB 优先级
        set_state(1,1, 100,200, 0,0,0, 1,1,222, 1,1,333);
        #10;
        check("MEM > WB", op1==222, op2==222);

        // 多源匹配不同寄存器
        set_state(1,2, 100,200, 1,0,111, 0,2,222, 0,0,0);
        #10;
        check("rs1 EX2, rs2 MEM", op1==111, op2==222);

        // x0 不旁路
        set_state(0,0, 100,200, 1,0,111, 0,0,0, 0,0,0);
        #10;
        check("x0 no bypass", op1==0, op2==0);

        $display("=================================");
        if (errors == 0) $display("Bypass ALL TESTS PASSED!");
        else $display("Bypass TEST FAILED with %0d errors.", errors);
        $finish;
    end

    task set_state(int raddr1, raddr2,
                   int r1, r2,
                   int e_wen, e_rd, e_res,
                   int m_wen, m_rd, m_res,
                   int w_wen, w_rd, w_res);
        rs1_addr = raddr1; rs2_addr = raddr2;
        rf_rs1 = r1; rf_rs2 = r2;
        ex2_wen = e_wen; ex2_rd = e_rd; ex2_result = e_res;
        mem_wen = m_wen; mem_rd = m_rd; mem_result = m_res;
        wb_wen  = w_wen; wb_rd  = w_rd;  wb_result  = w_res;
    endtask

    task check(string msg, int exp1, int exp2);
        if (op1 !== exp1 || op2 !== exp2) begin
            $error("[%s] Mismatch: op1=%h (exp %h), op2=%h (exp %h)", msg, op1, exp1, op2, exp2);
            errors++;
        end
    endtask

endmodule