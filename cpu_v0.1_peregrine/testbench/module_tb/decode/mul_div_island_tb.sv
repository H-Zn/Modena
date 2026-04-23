import cpu_pkg::*;

module tb_mul_div_island;

    logic        clk, rst_n, flush;
    logic        valid;
    logic [2:0]  mul_div_op;
    logic [31:0] opa, opb;
    logic        busy;
    logic [31:0] result;
    logic        result_valid;

    mul_div_island dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (flush),
        .valid_i         (valid),
        .mul_div_op_i    (mul_div_op),
        .opa_i           (opa),
        .opb_i           (opb),
        .busy_o          (busy),
        .result_o        (result),
        .result_valid_o  (result_valid)
    );

    always #5 clk = ~clk;
    initial clk = 0;

    int errors = 0;

    // 等待结果
    task wait_result();
        while (!result_valid) @(posedge clk);
    endtask

    initial begin
        rst_n = 0; flush = 0; valid = 0; mul_div_op = 0; opa = 0; opb = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // 乘法测试
        $display("[MUL] Testing multiplication...");
        test_mul(3'b000, 10, 20, 200);        // MUL
        test_mul(3'b001, -10, 20, -200);       // MULH (high part)
        test_mul(3'b010, -10, 20, -1);         // MULHSU (signed*unsigned, high)
        test_mul(3'b011, 10, 20, 0);           // MULHU (unsigned*unsigned, high)
        test_mul(3'b000, 0, 0, 0);
        test_mul(3'b000, -1, -1, 1);

        // 除法测试 (多周期)
        $display("[DIV] Testing division...");
        test_div(3'b100, 20, 10, 2);     // DIV
        test_div(3'b101, 20, 10, 2);     // DIVU
        test_div(3'b110, 20, 10, 2);     // REM
        test_div(3'b111, 20, 10, 2);     // REMU
        test_div(3'b100, -20, 10, -2);
        test_div(3'b100, 20, -10, -2);
        test_div(3'b100, -20, -10, 2);
        test_div(3'b100, 0, 10, 0);      // 0/x=0
        test_div(3'b100, 10, 0, -1);     // x/0 (RISC-V要求全1商)
        test_div(3'b110, 10, 0, 10);     // REM x/0 余数为被除数

        $display("=================================");
        if (errors == 0) $display("MUL/DIV ALL TESTS PASSED!");
        else $display("MUL/DIV TEST FAILED with %0d errors.", errors);
        $finish;
    end

    // 乘法测试任务
    task test_mul(logic [2:0] op, int a, int b, int exp);
        valid = 1; mul_div_op = op; opa = a; opb = b;
        @(posedge clk);
        valid = 0;
        wait_result();
        if (result !== exp) begin
            $error("[MUL] op=%b, %d * %d, got=%d, exp=%d", op, a, b, result, exp);
            errors++;
        end else $display("  PASS: %d op %d = %d", a, b, result);
    endtask

    // 除法测试任务
    task test_div(logic [2:0] op, int a, int b, int exp);
        valid = 1; mul_div_op = op; opa = a; opb = b;
        @(posedge clk);
        valid = 0;
        wait_result();
        if (result !== exp) begin
            $error("[DIV] op=%b, %d div/rem %d, got=%d, exp=%d", op, a, b, result, exp);
            errors++;
        end else $display("  PASS: %d op %d = %d", a, b, result);
    endtask

endmodule