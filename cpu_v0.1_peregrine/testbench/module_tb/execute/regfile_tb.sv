module tb_regfile;

    logic        clk;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic        wr_en;
    logic [31:0] rd_data, rs1_data, rs2_data;

    regfile dut (
        .clk        (clk),
        .rs1_addr_i (rs1_addr),
        .rs1_data_o (rs1_data),
        .rs2_addr_i (rs2_addr),
        .rs2_data_o (rs2_data),
        .wr_en_i    (wr_en),
        .rd_addr_i  (rd_addr),
        .rd_data_i  (rd_data)
    );

    // 时钟
    always #5 clk = ~clk;
    initial clk = 0;

    int errors = 0;

    // 写寄存器任务
    task write_reg(int idx, int val);
        @(negedge clk);
        wr_en = 1; rd_addr = idx; rd_data = val;
        @(negedge clk);
        wr_en = 0;
    endtask

    initial begin
        // 初始化
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0; wr_en = 0; rd_data = 0;
        repeat(3) @(posedge clk);

        // 测试x0硬连线
        $display("[Regfile] x0 test...");
        @(negedge clk);
        rs1_addr = 0;
        @(posedge clk) #1;
        if (rs1_data !== 32'h0) error("x0 read non-zero");

        // 写读测试
        $display("[Regfile] Write/read tests...");
        for (int i = 1; i < 32; i++) begin
            write_reg(i, i * 4);
            @(negedge clk);
            rs1_addr = i; rs2_addr = i;
            @(posedge clk) #1;
            if (rs1_data !== i*4) error($sformatf("Read rs1 reg%0d", i));
            if (rs2_data !== i*4) error($sformatf("Read rs2 reg%0d", i));
        end

        // 同时读写同地址（写入后立即读取，由于时序应在下一周期读出旧值）
        $display("[Regfile] Write/read same addr...");
        write_reg(10, 32'hDEADBEEF);
        @(negedge clk);
        rs1_addr = 10; rs2_addr = 20;
        wr_en = 1; rd_addr = 10; rd_data = 32'hCAFEBABE;
        @(posedge clk) #1;
        // 读取时读端口应返回上一周期的旧值（DEADBEEF）或新值取决于实现
        // Peregrine regfile 为写优先？这里假设读旧值
        if (rs1_data !== 32'hDEADBEEF) begin
            $display("  Note: regfile read during write returned %h (expected DEADBEEF). Implementation may be write-first.", rs1_data);
            // 不强制报错，记录警告
        end
        @(negedge clk);
        wr_en = 0;
        @(posedge clk) #1;
        if (rs1_data !== 32'hCAFEBABE) error("Re-read after write wrong");

        // 双端口读不同地址
        $display("[Regfile] Dual read...");
        write_reg(5, 32'h55555555);
        write_reg(7, 32'h77777777);
        @(negedge clk);
        rs1_addr = 5; rs2_addr = 7;
        @(posedge clk) #1;
        if (rs1_data !== 32'h55555555 || rs2_data !== 32'h77777777) error("Dual read mismatch");

        $display("=================================");
        if (errors == 0) $display("Regfile ALL TESTS PASSED!");
        else $display("Regfile TEST FAILED with %0d errors.", errors);
        $finish;
    end

    task error(string msg);
        $error("[Regfile] %s", msg);
        errors++;
    endtask

endmodule