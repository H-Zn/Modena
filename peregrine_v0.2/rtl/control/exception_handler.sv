// exception_handler.sv
import cpu_pkg::*;

module exception_handler (
    input  logic        clk,
    input  logic        rst_n,

    // 来自各流水级的异常标志
    input  logic        id_illegal_i,      // ID 非法指令
    input  logic [31:0] id_pc_i,
    input  logic [31:0] id_inst_i,

    input  logic        ex1_misaligned_i,  // AGU 地址未对齐
    input  logic [31:0] ex1_pc_i,
    input  logic [31:0] ex1_addr_i,

    input  logic        ex2_ecall_i,
    input  logic        ex2_ebreak_i,
    input  logic        ex2_div_zero_i,
    input  logic [31:0] ex2_pc_i,

    input  logic        mem_access_fault_i,
    input  logic        mem_page_fault_i,
    input  logic [31:0] mem_pc_i,
    input  logic [31:0] mem_addr_i,

    // 中断请求
    input  logic        ext_irq_i,         // 外部中断 (MEIP/SEIP)
    input  logic        timer_irq_i,       // 定时器中断 (MTIP/STIP)
    input  logic        soft_irq_i,        // 软件中断 (MSIP/SSIP)

    // CSR 指令接口 (来自 ID/EX)
    input  logic        csr_wr_en_i,
    input  logic [11:0] csr_addr_i,
    input  logic [31:0] csr_wdata_i,
    output logic [31:0] csr_rdata_o,

    // 冲刷请求输出
    output logic        exc_req_o,
    output logic [31:0] exc_target_o,

    // 异常/中断状态 (供 perf_counters 等)
    output logic        exception_taken_o,
    output logic        interrupt_taken_o
);

    // ---------- CSR 寄存器定义 ----------
    // M 模式 CSR
    logic [31:0] mstatus, mcause, mtvec, mepc, mtval, mip, mie, mscratch, mideleg;
    logic [31:0] mhartid;
    // S 模式 CSR (简化)
    logic [31:0] sstatus, scause, stvec, sepc, stval, sip, sie, sscratch;

    // 特权模式
    typedef enum logic [1:0] {M_MODE=2'b11, S_MODE=2'b01, U_MODE=2'b00} priv_mode_t;
    priv_mode_t priv_mode;

    // ---------- 异常收集 ----------
    logic        exc_valid;
    exc_code_t   exc_code;
    logic [31:0] exc_pc;
    logic [31:0] exc_tval;
    logic        is_interrupt;

    always_comb begin
        exc_valid = 1'b0;
        exc_code  = EXC_ILLEGAL_INST;
        exc_pc    = 32'h0;
        exc_tval  = 32'h0;
        is_interrupt = 1'b0;

        // 中断采样 (优先级: MEI > MSI > MTI > SEI > SSI > STI)
        // 仅当全局中断使能 (mstatus.MIE/SIE) 且对应使能位有效
        if (ext_irq_i && (mip[11] & mie[11]) && mstatus[3]) begin
            is_interrupt = 1'b1;
            exc_code = 4'd11; // Machine external interrupt
        end else if (soft_irq_i && (mip[3] & mie[3]) && mstatus[3]) begin
            is_interrupt = 1'b1;
            exc_code = 4'd3;  // Machine software interrupt
        end else if (timer_irq_i && (mip[7] & mie[7]) && mstatus[3]) begin
            is_interrupt = 1'b1;
            exc_code = 4'd7;  // Machine timer interrupt
        // 异常检测 (按优先级)
        end else if (id_illegal_i) begin
            exc_valid = 1'b1;
            exc_code = EXC_ILLEGAL_INST;
            exc_pc   = id_pc_i;
            exc_tval = id_inst_i;
        end else if (ex1_misaligned_i) begin
            exc_valid = 1'b1;
            exc_code = EXC_LOAD_MISALIGNED; // 或 STORE
            exc_pc   = ex1_pc_i;
            exc_tval = ex1_addr_i;
        end else if (ex2_ecall_i) begin
            exc_valid = 1'b1;
            exc_pc   = ex2_pc_i;
            case (priv_mode)
                M_MODE: exc_code = EXC_ECALL_M;
                S_MODE: exc_code = EXC_ECALL_S;
                U_MODE: exc_code = EXC_ECALL_U;
            endcase
        end else if (ex2_ebreak_i) begin
            exc_valid = 1'b1;
            exc_code = EXC_BREAKPOINT;
            exc_pc   = ex2_pc_i;
        end else if (mem_page_fault_i) begin
            exc_valid = 1'b1;
            exc_code = EXC_LOAD_PAGE_FAULT; // 或 STORE
            exc_pc   = mem_pc_i;
            exc_tval = mem_addr_i;
        end else if (mem_access_fault_i) begin
            exc_valid = 1'b1;
            exc_code = EXC_LOAD_ACCESS;
            exc_pc   = mem_pc_i;
            exc_tval = mem_addr_i;
        end
    end

    // ---------- CSR 读写逻辑 ----------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus  <= 32'h00001800; // MPP=M-mode, MIE=0
            mcause   <= 32'h0;
            mtvec    <= 32'h0;
            mepc     <= 32'h0;
            mtval    <= 32'h0;
            mip      <= 32'h0;
            mie      <= 32'h0;
            mscratch <= 32'h0;
            mideleg  <= 32'h0;
            sstatus  <= 32'h0;
            scause   <= 32'h0;
            stvec    <= 32'h0;
            sepc     <= 32'h0;
            stval    <= 32'h0;
            sip      <= 32'h0;
            sie      <= 32'h0;
            sscratch <= 32'h0;
            priv_mode<= M_MODE;
        end else begin
            // 异常/中断触发时的自动 CSR 更新
            if (exc_valid || is_interrupt) begin
                // 保存现场
                mepc   <= exc_pc;
                mcause <= {is_interrupt, 26'h0, exc_code};
                mtval  <= exc_tval;
                // 更新 mstatus: MPP <- priv_mode, MPIE <- MIE, MIE <- 0
                mstatus[12:11] <= priv_mode;
                mstatus[7] <= mstatus[3];
                mstatus[3] <= 1'b0;
                // 跳转到 mtvec
                // priv_mode 切换为 M
                priv_mode <= M_MODE;
            end

            // CSR 指令写 (在 WB 阶段)
            if (csr_wr_en_i) begin
                case (csr_addr_i)
                    12'h300: mstatus <= csr_wdata_i;
                    12'h305: mtvec   <= csr_wdata_i;
                    12'h341: mepc    <= csr_wdata_i;
                    12'h342: mcause  <= csr_wdata_i;
                    12'h343: mtval   <= csr_wdata_i;
                    12'h304: mie     <= csr_wdata_i;
                    12'h344: mip     <= csr_wdata_i;
                    12'h340: mscratch<= csr_wdata_i;
                    12'h303: mideleg <= csr_wdata_i;
                    12'h100: sstatus <= csr_wdata_i;
                    12'h105: stvec   <= csr_wdata_i;
                    12'h141: sepc    <= csr_wdata_i;
                    12'h142: scause  <= csr_wdata_i;
                    12'h143: stval   <= csr_wdata_i;
                    12'h104: sie     <= csr_wdata_i;
                    12'h144: sip     <= csr_wdata_i;
                    12'h140: sscratch<= csr_wdata_i;
                    default: ;
                endcase
            end

            // 中断置位 (简化：外部连接至 mip)
            mip[11] <= ext_irq_i;
            mip[7]  <= timer_irq_i;
            mip[3]  <= soft_irq_i;
        end
    end

    // CSR 读
    always_comb begin
        csr_rdata_o = 32'h0;
        case (csr_addr_i)
            12'h300: csr_rdata_o = mstatus;
            12'h305: csr_rdata_o = mtvec;
            12'h341: csr_rdata_o = mepc;
            12'h342: csr_rdata_o = mcause;
            12'h343: csr_rdata_o = mtval;
            12'h304: csr_rdata_o = mie;
            12'h344: csr_rdata_o = mip;
            12'h340: csr_rdata_o = mscratch;
            12'h303: csr_rdata_o = mideleg;
            12'h100: csr_rdata_o = sstatus;
            12'h105: csr_rdata_o = stvec;
            12'h141: csr_rdata_o = sepc;
            12'h142: csr_rdata_o = scause;
            12'h143: csr_rdata_o = stval;
            12'h104: csr_rdata_o = sie;
            12'h144: csr_rdata_o = sip;
            12'h140: csr_rdata_o = sscratch;
            12'hf14: csr_rdata_o = mhartid;
            default: csr_rdata_o = 32'h0;
        endcase
    end

    // 冲刷请求输出
    assign exc_req_o = exc_valid || is_interrupt;
    assign exc_target_o = (is_interrupt || exc_code inside {EXC_ECALL_M, EXC_ECALL_S, EXC_ECALL_U}) ?
                          mtvec : mtvec;  // 简化：所有异常/中断都跳 mtvec

    assign exception_taken_o = exc_valid;
    assign interrupt_taken_o = is_interrupt;

endmodule