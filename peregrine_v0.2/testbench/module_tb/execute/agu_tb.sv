module tb_agu;

    logic [31:0] base, offset;
    logic [31:0] addr;
    logic        misaligned;

    agu dut (
        .base_i      (base),
        .offset_i    (offset),
        .addr_o      (addr),
        .misaligned_o(misaligned)
    );

    int errors = 0;

    initial begin
        $display("[AGU] Directed and random tests...");

        // 定向测试
        base = 32'h00001000; offset = 32'h00000000; #10;
        check("Zero offset", 32'h00001000);

        base = 32'h00001000; offset = 32'h00000004; #10;
        check("Positive offset", 32'h00001004);

        base = 32'h00001000; offset = 32'hFFFFFFFC; #10; // -4
        check("Negative offset", 32'h00000FFC);

        base = 32'hFFFFFFFF; offset = 32'h00000001; #10;
        check("Wrap around", 32'h00000000);

        base = 32'h7FFFFFFF; offset = 32'h00000001; #10;
        check("Overflow to negative", 32'h80000000);

        // 随机测试
        for (int i = 0; i < 500; i++) begin
            base = $urandom();
            offset = $urandom();
            #10;
            check($sformatf("Random %0d", i), base + offset);
        end

        $display("=================================");
        if (errors == 0) $display("AGU ALL TESTS PASSED!");
        else $display("AGU TEST FAILED with %0d errors.", errors);
        $finish;
    end

    task automatic check(string msg, logic [31:0] exp);
        if (addr !== exp) begin
            $error("[%s] AGU mismatch: base=%h, offset=%h, got=%h, exp=%h",
                   msg, base, offset, addr, exp);
            errors++;
        end
    endtask

endmodule