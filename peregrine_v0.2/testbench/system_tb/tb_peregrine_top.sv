// tb_peregrine_top.sv
// Basic system-level testbench for Peregrine CPU
`timescale 1ns / 1ps

module tb_peregrine_top;

    logic clk;
    logic rst_n;
    logic irq_software, irq_timer, irq_external;

    logic        m_axi_awvalid;
    logic        m_axi_awready;
    logic [31:0] m_axi_awaddr;
    logic [ 7:0] m_axi_awlen;
    logic [ 2:0] m_axi_awsize;
    logic [ 1:0] m_axi_awburst;

    logic        m_axi_wvalid;
    logic        m_axi_wready;
    logic [31:0] m_axi_wdata;
    logic [ 3:0] m_axi_wstrb;
    logic        m_axi_wlast;

    logic        m_axi_bvalid;
    logic        m_axi_bready;
    logic [ 1:0] m_axi_bresp;

    logic        m_axi_arvalid;
    logic        m_axi_arready;
    logic [31:0] m_axi_araddr;
    logic [ 7:0] m_axi_arlen;
    logic [ 2:0] m_axi_arsize;
    logic [ 1:0] m_axi_arburst;

    logic        m_axi_rvalid;
    logic        m_axi_rready;
    logic [31:0] m_axi_rdata;
    logic        m_axi_rlast;
    logic [ 1:0] m_axi_rresp;

    logic jtag_tck, jtag_tms, jtag_tdi, jtag_tdo;

    peregrine_top #(
        .ICACHE_EN(1),
        .DCACHE_EN(1),
        .ITCM_EN(1),
        .DTCM_EN(0),
        .M_EXT_EN(1),
        .A_EXT_EN(0),
        .ZICSR_EN(1),
        .ZIFENCEI_EN(1),
        .S_MODE_EN(0),
        .PMU_EN(1)
    ) uut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .irq_software_i (irq_software),
        .irq_timer_i    (irq_timer),
        .irq_external_i (irq_external),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rresp    (m_axi_rresp),
        .jtag_tck       (jtag_tck),
        .jtag_tms       (jtag_tms),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo)
    );

    // AXI Slave Memory Model (simplified)
    logic [31:0] mem [0:1023];

    initial begin
        $readmemh("test_program.hex", mem);
    end

    // AXI Read Slave
    logic [7:0] rd_burst_cnt;
    logic [31:0] rd_addr_reg;
    logic rd_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready  <= 1'b1;
            m_axi_rvalid   <= 1'b0;
            m_axi_rdata    <= 32'h0;
            m_axi_rlast    <= 1'b0;
            m_axi_rresp    <= 2'b00;
            rd_burst_cnt   <= 8'h0;
            rd_active      <= 1'b0;
            rd_addr_reg    <= 32'h0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                rd_addr_reg  <= m_axi_araddr;
                rd_burst_cnt <= 8'h0;
                rd_active    <= 1'b1;
                m_axi_arready<= 1'b0;
            end

            if (rd_active) begin
                m_axi_rvalid <= 1'b1;
                m_axi_rdata  <= mem[(rd_addr_reg[31:2] + rd_burst_cnt) & 10'h3FF];
                m_axi_rlast  <= (rd_burst_cnt == m_axi_arlen);
                if (m_axi_rready && m_axi_rvalid) begin
                    rd_burst_cnt <= rd_burst_cnt + 1'b1;
                    if (rd_burst_cnt == m_axi_arlen) begin
                        rd_active   <= 1'b0;
                        m_axi_rvalid<= 1'b0;
                        m_axi_rlast <= 1'b0;
                        m_axi_arready <= 1'b1;
                    end
                end
            end
        end
    end

    // AXI Write Slave (stub)
    assign m_axi_awready = 1'b1;
    assign m_axi_wready  = 1'b1;
    assign m_axi_bvalid  = 1'b0;
    assign m_axi_bresp   = 2'b00;

    // Clock generation: 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Test sequence
    initial begin
        rst_n = 1'b0;
        irq_software = 1'b0;
        irq_timer    = 1'b0;
        irq_external = 1'b0;
        jtag_tck     = 1'b0;
        jtag_tms     = 1'b0;
        jtag_tdi     = 1'b0;

        // Hold reset for 100ns
        #100;
        rst_n = 1'b1;

        // Run for 1000 clock cycles
        #10000;

        $display("=== Test Complete ===");
        $display("Time: %0t", $time);
        $finish;
    end

    // Monitor for waveform
    initial begin
        $dumpfile("peregrine_tb.vcd");
        $dumpvars(0, tb_peregrine_top);
    end

endmodule
