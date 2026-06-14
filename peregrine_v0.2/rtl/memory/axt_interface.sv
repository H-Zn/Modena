// axi_interface.sv
import cpu_pkg::*;

module axi_interface (
    input  logic        clk,
    input  logic        rst_n,

    // 内部请求接口 (来自 MSHR 读缺失 / Writeback Sync 写回)
    input  logic        rd_req_valid_i,
    input  logic [31:0] rd_req_addr_i,
    output logic        rd_req_ready_o,
    output logic        rd_rsp_valid_o,
    output logic [31:0] rd_rsp_data_o,
    output logic        rd_rsp_last_o,
    output logic [ 1:0] rd_rsp_resp_o,

    input  logic        wr_req_valid_i,
    input  logic [31:0] wr_req_addr_i,
    input  logic [31:0] wr_req_data_i,
    input  logic [ 3:0] wr_req_strb_i,
    output logic        wr_req_ready_o,
    output logic        wr_rsp_valid_o,
    output logic [ 1:0] wr_rsp_resp_o,

    // AXI4 总线信号 (Master)
    // 写地址通道
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_awaddr,
    output logic [ 7:0] m_axi_awlen,
    output logic [ 2:0] m_axi_awsize,
    output logic [ 1:0] m_axi_awburst,

    // 写数据通道
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    output logic [31:0] m_axi_wdata,
    output logic [ 3:0] m_axi_wstrb,
    output logic        m_axi_wlast,

    // 写响应通道
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    input  logic [ 1:0] m_axi_bresp,

    // 读地址通道
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    output logic [31:0] m_axi_araddr,
    output logic [ 7:0] m_axi_arlen,
    output logic [ 2:0] m_axi_arsize,
    output logic [ 1:0] m_axi_arburst,

    // 读数据通道
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,
    input  logic [31:0] m_axi_rdata,
    input  logic        m_axi_rlast,
    input  logic [ 1:0] m_axi_rresp
);

    // 写地址通道 FSM
    typedef enum logic [1:0] {WIDLE, WAIT_AW, WAIT_W} wstate_t;
    wstate_t wstate, wstate_next;
    logic [7:0] wburst_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= WIDLE;
            wburst_cnt <= '0;
        end else begin
            wstate <= wstate_next;
            // 突发计数
            if (wstate == WAIT_W && m_axi_wvalid && m_axi_wready)
                wburst_cnt <= wburst_cnt + 1;
            else if (wstate == WIDLE)
                wburst_cnt <= '0;
        end
    end

    always_comb begin
        wstate_next = wstate;
        case (wstate)
            WIDLE: if (wr_req_valid_i) wstate_next = WAIT_AW;
            WAIT_AW: if (m_axi_awvalid && m_axi_awready) wstate_next = WAIT_W;
            WAIT_W: if (m_axi_wvalid && m_axi_wready && m_axi_wlast) wstate_next = WIDLE;
        endcase
    end

    // 写地址通道信号
    assign m_axi_awvalid = (wstate == WAIT_AW);
    assign m_axi_awaddr  = wr_req_addr_i;
    assign m_axi_awlen   = 8'h00; // 单拍写
    assign m_axi_awsize  = 3'b010; // 4 bytes
    assign m_axi_awburst = 2'b01; // INCR

    // 写数据通道
    assign m_axi_wvalid = (wstate == WAIT_W);
    assign m_axi_wdata  = wr_req_data_i;
    assign m_axi_wstrb  = wr_req_strb_i;
    assign m_axi_wlast  = (wburst_cnt == m_axi_awlen);

    // 写响应
    assign m_axi_bready = 1'b1;
    assign wr_rsp_valid_o = m_axi_bvalid;
    assign wr_rsp_resp_o  = m_axi_bresp;

    // 读通道 (简化实现，突发长度固定 8 拍)
    typedef enum logic [1:0] {RIDLE, RREQ, RDATA} rstate_t;
    rstate_t rstate, rstate_next;
    logic [7:0] rburst_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate <= RIDLE;
            rburst_cnt <= '0;
        end else begin
            rstate <= rstate_next;
            if (rstate == RDATA && m_axi_rvalid && m_axi_rready) begin
                if (m_axi_rlast)
                    rburst_cnt <= '0;
                else
                    rburst_cnt <= rburst_cnt + 1;
            end
        end
    end

    always_comb begin
        rstate_next = rstate;
        case (rstate)
            RIDLE: if (rd_req_valid_i) rstate_next = RREQ;
            RREQ: if (m_axi_arvalid && m_axi_arready) rstate_next = RDATA;
            RDATA: if (m_axi_rvalid && m_axi_rready && m_axi_rlast) rstate_next = RIDLE;
        endcase
    end

    assign m_axi_arvalid = (rstate == RREQ);
    assign m_axi_araddr  = rd_req_addr_i;
    assign m_axi_arlen   = 8'h07; // 8 beats
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;

    assign m_axi_rready = (rstate == RDATA);
    assign rd_rsp_valid_o = m_axi_rvalid;
    assign rd_rsp_data_o  = m_axi_rdata;
    assign rd_rsp_last_o  = m_axi_rlast;
    assign rd_rsp_resp_o  = m_axi_rresp;

    assign rd_req_ready_o = (rstate == RIDLE);
    assign wr_req_ready_o = (wstate == WIDLE);

endmodule