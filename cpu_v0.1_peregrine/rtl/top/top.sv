// peregrine_top.sv
`timescale 1ns / 1ps
import cpu_pkg::*;

module peregrine_top #(
    parameter CORE_ID = 0,                     // 多核 ID（预留）
    parameter ICACHE_EN = 1,
    parameter DCACHE_EN = 1,
    parameter ITCM_EN = 1,
    parameter DTCM_EN = 1,
    parameter M_EXT_EN = 1,
    parameter A_EXT_EN = 1,
    parameter ZICSR_EN = 1,
    parameter ZIFENCEI_EN = 1,
    parameter S_MODE_EN = 1,
    parameter PMU_EN = 1
) (
    // 系统时钟与复位
    input  logic        clk_i,
    input  logic        rst_n_i,

    // 中断输入
    input  logic        irq_software_i,    // 来自 CLINT 软件中断
    input  logic        irq_timer_i,       // 来自 CLINT 定时器中断
    input  logic        irq_external_i,    // 来自 PLIC 外部中断

    // AXI4 存储器接口
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
    input  logic [ 1:0] m_axi_rresp,

    // 调试接口 (JTAG)
    input  logic        jtag_tck,
    input  logic        jtag_tms,
    input  logic        jtag_tdi,
    output logic        jtag_tdo
);

    // ---------- 内部时钟与复位 ----------
    logic clk;
    logic rst_n;

    clk_rst_manager clk_rst_manager_inst (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .clk_o        (clk),
        .rst_sync_n_o (rst_n),
        .pll_locked_o ()
    );

    // ---------- 流水线寄存器定义 ----------
    // IF/ID 寄存器
    logic [31:0] if_pc, id_pc;
    logic [31:0] if_inst, id_inst;
    logic        if_pred_dir, id_pred_dir;
    logic [31:0] if_pred_target, id_pred_target;
    logic        if_fold_en, id_fold_en;

    // ID/EX1 寄存器
    micro_op_t   id_micro_op, ex1_micro_op;
    logic [31:0] id_pc_ex1, ex1_pc;
    logic        id_illegal, ex1_illegal;

    // EX1/EX2 寄存器
    logic [31:0] ex1_addr, ex2_addr;           // AGU 结果或传递
    logic [31:0] ex1_opa, ex2_opa;
    logic [31:0] ex1_opb, ex2_opb;
    logic [ 3:0] ex1_alu_op, ex2_alu_op;
    logic [ 2:0] ex1_branch_type, ex2_branch_type;
    logic        ex1_is_branch, ex2_is_branch;
    logic        ex1_is_jal, ex2_is_jal;
    logic        ex1_is_jalr, ex2_is_jalr;
    logic [31:0] ex1_pc_ex2, ex2_pc;
    logic [31:0] ex1_imm, ex2_imm;
    logic [ 4:0] ex1_rd_addr, ex2_rd_addr;
    logic        ex1_rd_wen, ex2_rd_wen;
    logic        ex1_mem_read, ex2_mem_read;
    logic        ex1_mem_write, ex2_mem_write;
    logic [ 1:0] ex1_mem_width, ex2_mem_width;
    logic        ex1_mem_sign_ext, ex2_mem_sign_ext;
    logic [ 3:0] ex1_wmask, ex2_wmask;
    // 乘除法相关
    logic        ex1_is_mul_div, ex2_is_mul_div;
    logic [ 2:0] ex1_mul_div_op, ex2_mul_div_op;

    // EX2/EX3 寄存器
    logic [31:0] ex2_result, ex3_result;
    logic [31:0] ex2_store_data, ex3_store_data;
    logic [ 4:0] ex2_rd_addr_ex3, ex3_rd_addr;
    logic        ex2_rd_wen_ex3, ex3_rd_wen;
    logic        ex2_exception, ex3_exception;
    exc_code_t   ex2_exc_code, ex3_exc_code;
    logic [31:0] ex2_pc_ex3, ex3_pc;
    logic        ex2_mem_read, ex3_mem_read;
    logic        ex2_mem_write, ex3_mem_write;
    logic [ 1:0] ex2_mem_width, ex3_mem_width;
    logic        ex2_mem_sign_ext, ex3_mem_sign_ext;
    logic [ 3:0] ex2_wmask, ex3_wmask;
    logic [31:0] ex2_addr_ex3, ex3_addr;

    // EX3/MEM 寄存器（可合并至 EX3 或单独定义）
    // 此处将 EX3 直接连接到 MEM 阶段

    // ---------- 停顿与冲刷信号 ----------
    logic stall_if, stall_id, stall_ex1;
    logic flush_if, flush_id, flush_ex1, flush_ex2;
    logic pc_redirect_valid;
    logic [31:0] pc_redirect_target;

    // 各模块产生的停顿请求
    logic dep_stall, maq_full_stall, eiq_full_stall, srb_stall;
    logic icache_miss_stall, dcache_miss_stall;

    assign stall_if = icache_miss_stall | stall_id;
    assign stall_id = dep_stall | maq_full_stall | eiq_full_stall;
    assign stall_ex1 = dcache_miss_stall | srb_stall;

    // ---------- 前端模块实例化 ----------
    logic [31:0] pc;
    logic        pred_dir;
    logic [31:0] pred_target;
    logic        fold_en;

    pc_gen pc_gen_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .pred_dir     (pred_dir),
        .pred_target  (pred_target),
        .fold_en      (fold_en),
        .flush        (flush_if),
        .flush_target (pc_redirect_target),
        .stall        (stall_if),
        .pc           (pc)
    );

    // 感知器预测器
    logic [7:0] pred_conf;
    logic       update_pred_valid;
    logic [31:0] update_pred_pc;
    logic       update_pred_taken;

    perceptron_predictor perceptron_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .pc_query     (pc),
        .pred_dir     (pred_dir),
        .conf         (pred_conf),
        .update_valid (update_pred_valid),
        .update_pc    (update_pred_pc),
        .update_taken (update_pred_taken)
    );

    // BTB
    logic btb_hit;
    logic [31:0] btb_target;
    logic btb_update_valid;
    logic [31:0] btb_update_pc, btb_update_target;

    btb btb_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_query      (pc),
        .hit           (btb_hit),
        .target        (btb_target),
        .update_valid  (btb_update_valid),
        .update_pc     (btb_update_pc),
        .update_target (btb_update_target)
    );

    // RAS
    logic ras_push, ras_pop;
    logic [31:0] ras_push_addr, ras_pred_target;
    logic ras_empty;

    ras ras_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .push_valid  (ras_push),
        .push_addr   (ras_push_addr),
        .pop_valid   (ras_pop),
        .pred_target (ras_pred_target),
        .empty       (ras_empty)
    );

    // 分支折叠
    branch_folder branch_folder_inst (
        .is_branch   (/* 来自预译码 */),
        .pred_dir    (pred_dir),
        .conf        (pred_conf),
        .btb_hit     (btb_hit),
        .btb_target  (btb_target),
        .fold_en     (fold_en),
        .fold_target (pred_target)
    );

    // I-Cache
    logic        icache_req_ready;
    logic [31:0] icache_rdata;
    logic        icache_rsp_valid;

    icache icache_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_pc       (pc),
        .req_valid    (!stall_if),
        .req_ready    (icache_req_ready),
        .rsp_data     (icache_rdata),
        .rsp_valid    (icache_rsp_valid),
        .axi_arvalid  (/* 连接 AXI 接口的仲裁器 */),
        .axi_arready  (),
        .axi_araddr   (),
        .axi_rvalid   (),
        .axi_rdata    ()
    );

    // ITCM (简化，地址译码在顶层)
    logic itcm_sel, itcm_rsp_valid;
    logic [31:0] itcm_rdata;

    if (ITCM_EN) begin : gen_itcm
        itcm #(.SIZE_KB(4)) itcm_inst (
            .clk        (clk),
            .rst_n      (rst_n),
            .req_addr   (pc),
            .req_valid  (!stall_if && itcm_sel),
            .rsp_data   (itcm_rdata),
            .rsp_valid  (itcm_rsp_valid)
        );
    end

    // 指令对齐器
    logic [31:0] aligned_inst;
    logic        align_valid;

    inst_aligner inst_aligner_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .raw_data   (icache_rdata), // 简化，实际需MUX ITCM
        .pc_low     (pc[1:0]),
        .valid_in   (icache_rsp_valid | itcm_rsp_valid),
        .ready      (),
        .inst_out   (aligned_inst),
        .valid_out  (align_valid)
    );

    // IF/ID 寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc         <= 32'h0;
            id_inst       <= 32'h0;
            id_pred_dir   <= 1'b0;
            id_pred_target<= 32'h0;
            id_fold_en    <= 1'b0;
        end else if (!stall_id) begin
            if (flush_id) begin
                id_pc   <= 32'h0;
                id_inst <= 32'h0;
                // 其他信号清零
            end else if (align_valid) begin
                id_pc         <= pc;
                id_inst       <= aligned_inst;
                id_pred_dir   <= pred_dir;
                id_pred_target<= pred_target;
                id_fold_en    <= fold_en;
            end
        end
    end

    // ---------- 译码与分发 ----------
    micro_op_t dec_micro_op;
    logic      dec_illegal;
    logic      dec_is_branch;  // 辅助信号

    decoder decoder_inst (
        .inst_i      (id_inst),
        .pc_i        (id_pc),
        .micro_op_o  (dec_micro_op),
        .illegal_o   (dec_illegal)
    );

    // 依赖检测
    dep_checker dep_checker_inst (
        .rs1_addr_i   (dec_micro_op.rs1_addr),
        .rs2_addr_i   (dec_micro_op.rs2_addr),
        .rs1_used_i   (dec_micro_op.rs1_used),
        .rs2_used_i   (dec_micro_op.rs2_used),
        .rd_ex1_i     (ex1_micro_op.rd_addr),
        .rd_wen_ex1_i (ex1_micro_op.rd_wen),
        .rd_ex2_i     (ex2_rd_addr),
        .rd_wen_ex2_i (ex2_rd_wen),
        .rd_ex3_i     (ex3_rd_addr),
        .rd_wen_ex3_i (ex3_rd_wen),
        .load_miss_i  (dcache_miss_stall),
        .mul_div_busy_i (/* M扩展忙信号 */),
        .stall_o      (dep_stall)
    );

    // MAQ 与 EIQ 写使能
    logic maq_wr, eiq_wr;
    maq_entry_t maq_wr_data;
    eiq_entry_t eiq_wr_data;

    dae_splitter dae_splitter_inst (
        .micro_op_i   (dec_micro_op),
        .stall_i      (dep_stall),
        .maq_wr_o     (maq_wr),
        .maq_data_o   (maq_wr_data),
        .eiq_wr_o     (eiq_wr),
        .eiq_data_o   (eiq_wr_data),
        .dual_issue_o ()
    );

    // ID/EX1 寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex1_micro_op <= '0;
            ex1_pc       <= 32'h0;
            ex1_illegal  <= 1'b0;
        end else if (!stall_ex1) begin
            if (flush_ex1) begin
                ex1_micro_op <= '0;
            end else begin
                ex1_micro_op <= dec_micro_op;
                ex1_pc       <= id_pc;
                ex1_illegal  <= dec_illegal;
            end
        end
    end

    // ---------- EX1 阶段：MAQ/EIQ/AGU/Regfile ----------
    logic maq_full, eiq_full;
    logic maq_rd_en, eiq_rd_en;
    maq_entry_t maq_rd_data;
    eiq_entry_t eiq_rd_data;

    maq maq_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .flush_i  (flush_ex1),
        .wr_en_i  (maq_wr),
        .wr_data_i(maq_wr_data),
        .full_o   (maq_full),
        .rd_en_i  (maq_rd_en),
        .rd_data_o(maq_rd_data),
        .empty_o  (),
        .stall_req_o(maq_full_stall)
    );

    eiq eiq_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .flush_i  (flush_ex1),
        .wr_en_i  (eiq_wr),
        .wr_data_i(eiq_wr_data),
        .full_o   (eiq_full),
        .rd_en_i  (eiq_rd_en),
        .rd_data_o(eiq_rd_data),
        .empty_o  (),
        .stall_req_o(eiq_full_stall)
    );

    // Regfile 读端口（组合逻辑）
    logic [31:0] rf_rs1_data, rf_rs2_data;
    regfile regfile_inst (
        .clk       (clk),
        .rs1_addr_i(ex1_micro_op.rs1_addr),
        .rs1_data_o(rf_rs1_data),
        .rs2_addr_i(ex1_micro_op.rs2_addr),
        .rs2_data_o(rf_rs2_data),
        .wr_en_i   (/* SRB 写回 */),
        .rd_addr_i (/* SRB 写回rd */),
        .rd_data_i (/* SRB 写回数据 */)
    );

    // 旁路网络（组合）
    logic [31:0] bypass_opa, bypass_opb;
    bypass_network bypass_inst (
        .rs1_addr_i   (ex1_micro_op.rs1_addr),
        .rs2_addr_i   (ex1_micro_op.rs2_addr),
        .rf_rs1_data_i(rf_rs1_data),
        .rf_rs2_data_i(rf_rs2_data),
        .ex2_rd_i     (ex2_rd_addr),
        .ex2_wen_i    (ex2_rd_wen),
        .ex2_result_i (ex2_result),
        .mem_rd_i     (ex3_rd_addr),
        .mem_wen_i    (ex3_rd_wen),
        .mem_result_i (ex3_result),
        .wb_rd_i      (/* SRB写回rd */),
        .wb_wen_i     (/* SRB写回wen */),
        .wb_result_i  (/* SRB写回数据 */),
        .op1_o        (bypass_opa),
        .op2_o        (bypass_opb)
    );

    // AGU（组合）
    logic [31:0] agu_addr;
    agu agu_inst (
        .base_i  (bypass_opa),
        .offset_i(ex1_micro_op.imm),
        .addr_o  (agu_addr),
        .misaligned_o()
    );

    // EX1/EX2 寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex2_addr <= 32'h0;
            ex2_opa  <= 32'h0;
            ex2_opb  <= 32'h0;
            // ... 其他信号
        end else if (!stall_ex1) begin
            if (flush_ex1) begin
                // 清零
            end else begin
                ex2_addr <= agu_addr;
                ex2_opa  <= bypass_opa;
                ex2_opb  <= bypass_opb;
                ex2_alu_op <= ex1_micro_op.alu_op;
                ex2_branch_type <= ex1_micro_op.branch_type;
                ex2_is_branch <= ex1_micro_op.is_branch;
                // ... 其他信号赋值
            end
        end
    end

    // ---------- EX2 阶段：执行岛 ----------
    logic [31:0] alu_result, mul_div_result;
    logic        mul_div_busy, mul_div_valid;

    alu_island alu_inst (
        .alu_op_i (ex2_alu_op),
        .opa_i    (ex2_opa),
        .opb_i    (ex2_opb),
        .result_o (alu_result)
    );

    if (M_EXT_EN) begin : gen_mul_div
        mul_div_island mul_div_inst (
            .clk        (clk),
            .rst_n      (rst_n),
            .flush_i    (flush_ex2),
            .valid_i    (ex2_is_mul_div),
            .mul_div_op_i(ex2_mul_div_op),
            .opa_i      (ex2_opa),
            .opb_i      (ex2_opb),
            .busy_o     (mul_div_busy),
            .result_o   (mul_div_result),
            .result_valid_o(mul_div_valid)
        );
    end

    // BRU Island
    logic        bru_flush, bru_mispred;
    logic [31:0] bru_flush_target;
    logic        bru_actual_taken;
    bru_island bru_inst (
        .branch_type_i (ex2_branch_type),
        .opa_i         (ex2_opa),
        .opb_i         (ex2_opb),
        .pc_i          (ex2_pc),
        .imm_i         (ex2_imm),
        .pred_dir_i    (id_pred_dir), // 需传递
        .flush_o       (bru_flush),
        .flush_target_o(bru_flush_target),
        .actual_taken_o(bru_actual_taken),
        .mispredict_o  (bru_mispred)
    );

    // 结果选择
    logic [31:0] ex2_result_int;
    assign ex2_result_int = ex2_is_mul_div ? mul_div_result : alu_result;

    // EX2/EX3 寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex3_result <= 32'h0;
            ex3_store_data <= 32'h0;
            // ...
        end else if (!stall_ex1) begin
            if (flush_ex2) begin
                // 清零
            end else begin
                ex3_result <= ex2_result_int;
                ex3_store_data <= ex2_opb; // Store数据来自rs2
                ex3_rd_addr <= ex2_rd_addr;
                ex3_rd_wen <= ex2_rd_wen;
                ex3_exception <= 1'b0;
                ex3_pc <= ex2_pc;
                ex3_mem_read <= ex2_mem_read;
                ex3_mem_write <= ex2_mem_write;
                ex3_mem_width <= ex2_mem_width;
                ex3_mem_sign_ext <= ex2_mem_sign_ext;
                ex3_wmask <= ex2_wmask;
                ex3_addr <= ex2_addr;
            end
        end
    end

    // ---------- 存储子系统 (D-Cache, TCM, MSHR, AXI) ----------
    logic dcache_rsp_valid, dcache_miss;
    logic [31:0] dcache_rdata;
    logic mshr_alloc_valid, mshr_alloc_ready;
    logic [31:0] mshr_alloc_addr;
    logic mshr_alloc_is_write;
    logic [1:0] mshr_alloc_id;

    dcache #(16*1024, 32, 4) dcache_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush_i        (flush_ex2),
        .req_valid_i    (ex3_mem_read | ex3_mem_write),
        .req_type_i     (ex3_mem_write ? MEM_REQ_STORE : MEM_REQ_LOAD),
        .req_addr_i     (ex3_addr),
        .req_wdata_i    (ex3_store_data),
        .req_wmask_i    (ex3_wmask),
        .req_is_atomic_i(1'b0),
        .req_atomic_op_i('0),
        .rsp_valid_o    (dcache_rsp_valid),
        .rsp_rdata_o    (dcache_rdata),
        .rsp_miss_o     (dcache_miss),
        .mshr_alloc_valid_o(mshr_alloc_valid),
        .mshr_alloc_addr_o (mshr_alloc_addr),
        .mshr_alloc_is_write_o(mshr_alloc_is_write),
        .mshr_alloc_ready_i(mshr_alloc_ready),
        .mshr_alloc_id_i(mshr_alloc_id),
        .mshr_fill_valid_i(1'b0), // 连接 AXI 返回
        .mshr_fill_id_i(2'b0),
        .mshr_fill_addr_i(32'b0),
        .mshr_fill_data_i(32'b0),
        .mshr_fill_last_i(1'b0),
        .wb_req_valid_o(/* 连接 Writeback Sync */),
        .wb_req_addr_o(),
        .wb_req_data_o(),
        .wb_req_mask_o(),
        .wb_req_ready_i(1'b0)
    );

    // DTCM（简化，地址译码类似ITCM）
    // ...

    // MSHR
    mshr #(4) mshr_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush_i         (flush_ex2),
        .alloc_valid_i   (mshr_alloc_valid),
        .alloc_addr_i    (mshr_alloc_addr),
        .alloc_is_write_i(mshr_alloc_is_write),
        .alloc_ready_o   (mshr_alloc_ready),
        .alloc_id_o      (mshr_alloc_id),
        .fill_req_valid_o(/* 至 AXI 读请求 */),
        .fill_req_addr_o (),
        .fill_req_is_write_o(),
        .fill_req_ready_i(),
        .fill_data_valid_i(),
        .fill_data_i     (),
        .fill_data_last_i(),
        .fill_done_valid_o(),
        .fill_done_id_o  ()
    );

    // AXI Interface
    axi_interface axi_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .rd_req_valid_i(/* MSHR 读请求 */),
        .rd_req_addr_i (),
        .rd_req_ready_o(),
        .rd_rsp_valid_o(),
        .rd_rsp_data_o (),
        .rd_rsp_last_o (),
        .rd_rsp_resp_o (),
        .wr_req_valid_i(/* Writeback Sync 写回请求 */),
        .wr_req_addr_i (),
        .wr_req_data_i (),
        .wr_req_strb_i (),
        .wr_req_ready_o(),
        .wr_rsp_valid_o(),
        .wr_rsp_resp_o (),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_arvalid (m_axi_arvalid),
        .m_axi_arready (m_axi_arready),
        .m_axi_araddr  (m_axi_araddr),
        .m_axi_arlen   (m_axi_arlen),
        .m_axi_arsize  (m_axi_arsize),
        .m_axi_arburst (m_axi_arburst),
        .m_axi_rvalid  (m_axi_rvalid),
        .m_axi_rready  (m_axi_rready),
        .m_axi_rdata   (m_axi_rdata),
        .m_axi_rlast   (m_axi_rlast),
        .m_axi_rresp   (m_axi_rresp)
    );

    // ---------- 提交阶段 SRB, Store Buffer, Writeback Sync ----------
    // 实例化 SRB
    logic srb_alloc_en, srb_alloc_full;
    logic [4:0] srb_alloc_idx;
    logic srb_result_wr_en;
    logic [4:0] srb_result_idx;
    logic [31:0] srb_result_data;
    logic srb_result_exception;
    exc_code_t srb_result_exc_code;
    logic srb_commit_valid;
    logic [4:0] srb_commit_rd_addr;
    logic [31:0] srb_commit_rd_data;
    logic srb_commit_rd_wen;
    logic srb_store_commit;
    logic [2:0] srb_store_commit_idx;
    logic srb_exc_req;
    logic [31:0] srb_exc_pc;
    exc_code_t srb_exc_code;
    logic srb_stall_wb;
    logic srb_instret_event;

    srb #(16) srb_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .flush_i          (flush_ex2),
        .alloc_en_i       (srb_alloc_en),
        .alloc_idx_o      (srb_alloc_idx),
        .alloc_full_o     (srb_alloc_full),
        .result_wr_en_i   (srb_result_wr_en),
        .result_idx_i     (srb_result_idx),
        .result_data_i    (srb_result_data),
        .result_exception_i(srb_result_exception),
        .result_exc_code_i(srb_result_exc_code),
        .commit_valid_o   (srb_commit_valid),
        .commit_rd_addr_o (srb_commit_rd_addr),
        .commit_rd_data_o (srb_commit_rd_data),
        .commit_rd_wen_o  (srb_commit_rd_wen),
        .store_commit_o   (srb_store_commit),
        .store_commit_idx_o(srb_store_commit_idx),
        .exc_req_o        (srb_exc_req),
        .exc_pc_o         (srb_exc_pc),
        .exc_code_o       (srb_exc_code),
        .stall_wb_o       (srb_stall_wb),
        .instret_event_o  (srb_instret_event)
    );

    // Store Buffer
    stb_entry_t stb_wr_data;
    logic stb_full, stb_empty;
    logic stb_forward_hit;
    logic [31:0] stb_forward_data;
    logic stb_wb_rd_en;
    stb_entry_t stb_wb_rd_data;

    store_buffer #(8) store_buffer_inst (
        .clk                (clk),
        .rst_n              (rst_n),
        .flush_i            (flush_ex2),
        .wr_en_i            (ex3_mem_write && !dcache_miss),
        .wr_addr_i          (ex3_addr),
        .wr_data_i          (ex3_store_data),
        .wr_mask_i          (ex3_wmask),
        .full_o             (stb_full),
        .commit_i           (srb_store_commit),
        .commit_idx_i       (srb_store_commit_idx),
        .load_addr_i        (ex3_addr), // MEM阶段Load地址
        .load_width_i       (ex3_mem_width),
        .forward_hit_o      (stb_forward_hit),
        .forward_data_o     (stb_forward_data),
        .wb_rd_en_i         (stb_wb_rd_en),
        .wb_rd_data_o       (stb_wb_rd_data),
        .empty_o            (stb_empty),
        .clear_uncommitted_i(flush_ex2)
    );

    // Writeback Sync
    writeback_sync writeback_sync_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .stb_rd_en_o      (stb_wb_rd_en),
        .stb_rd_data_i    (stb_wb_rd_data),
        .stb_empty_i      (stb_empty),
        .dcache_wr_req_o  (/* 连接 D-Cache 写回请求端口 */),
        .dcache_wr_addr_o (),
        .dcache_wr_data_o (),
        .dcache_wr_mask_o (),
        .dcache_wr_gnt_i  (),
        .dcache_wr_done_i (),
        .dcache_wr_miss_i (),
        .mshr_alloc_valid_o(),
        .mshr_alloc_addr_o(),
        .mshr_alloc_ready_i(),
        .mshr_fill_done_i ()
    );

    // ---------- 控制模块 ----------
    flush_controller flush_ctrl_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .exc_req_i         (srb_exc_req),
        .exc_target_i      (srb_exc_pc),
        .mispred_req_i     (bru_flush),
        .mispred_target_i  (bru_flush_target),
        .fencei_req_i      (1'b0), // 暂未连接
        .debug_req_i       (1'b0),
        .flush_if_o        (flush_if),
        .flush_id_o        (flush_id),
        .flush_ex1_o       (flush_ex1),
        .flush_ex2_o       (flush_ex2),
        .pc_redirect_valid_o(pc_redirect_valid),
        .pc_redirect_target_o(pc_redirect_target),
        .flush_event_o     (),
        .mispred_event_o   ()
    );

    exception_handler exc_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .id_illegal_i     (dec_illegal),
        .id_pc_i          (id_pc),
        .id_inst_i        (id_inst),
        .ex1_misaligned_i (1'b0),
        .ex1_pc_i         (ex1_pc),
        .ex1_addr_i       (ex1_micro_op.imm),
        .ex2_ecall_i      (ex1_micro_op.is_ecall),
        .ex2_ebreak_i     (ex1_micro_op.is_ebreak),
        .ex2_div_zero_i   (1'b0),
        .ex2_pc_i         (ex2_pc),
        .mem_access_fault_i(1'b0),
        .mem_page_fault_i (1'b0),
        .mem_pc_i         (ex3_pc),
        .mem_addr_i       (ex3_addr),
        .ext_irq_i        (irq_external_i),
        .timer_irq_i      (irq_timer_i),
        .soft_irq_i       (irq_software_i),
        .csr_wr_en_i      (1'b0), // 需要从译码连接 CSR 写
        .csr_addr_i       (12'b0),
        .csr_wdata_i      (32'b0),
        .csr_rdata_o      (),
        .exc_req_o        (), // 已通过 flush_controller
        .exc_target_o     (),
        .exception_taken_o(),
        .interrupt_taken_o()
    );

    // 性能计数器（可选）
    if (PMU_EN) begin : gen_pmu
        perf_counters perf_inst (
            .clk                (clk),
            .rst_n              (rst_n),
            .cycle_event_i      (1'b1),
            .instret_event_i    (srb_instret_event),
            .branch_mispred_event_i(bru_mispred),
            .data_stall_event_i (dep_stall),
            .control_stall_event_i(flush_if),
            .icache_miss_event_i(icache_miss_stall),
            .dcache_miss_event_i(dcache_miss_stall),
            .load_use_stall_event_i(1'b0),
            .csr_rd_en_i        (1'b0),
            .csr_rd_addr_i      (12'b0),
            .csr_rd_data_o      (),
            .cnt_sel_i          (3'b0),
            .event_sel_i        (3'b0),
            .cnt_wr_en_i        (1'b0)
        );
    end

    // 地址译码：ITCM / DTCM 选择
    assign itcm_sel = (pc >= 32'h0000_0000) && (pc < 32'h0000_1000); // 4KB

    // 连接更新预测器信号（示例）
    assign update_pred_valid = bru_flush; // 实际应在分支解析后更新
    assign update_pred_pc    = ex2_pc;
    assign update_pred_taken = bru_actual_taken;

    // 连接 BTB 更新
    assign btb_update_valid  = (ex2_is_jal | ex2_is_jalr | (ex2_is_branch & bru_actual_taken));
    assign btb_update_pc     = ex2_pc;
    assign btb_update_target = ex2_result_int; // 跳转目标

    // RAS 压栈/弹栈
    assign ras_push = ex1_micro_op.is_call; // JAL rd=x1/x5
    assign ras_push_addr = ex1_pc + 32'd4;
    assign ras_pop  = ex1_micro_op.is_ret;  // JALR rs1=x1/x5

    // 数据旁路网络连接到 EX2/EX3/SRB 写回信号（部分已在上面连接）
    // 需将 SRB 提交的数据也连接到旁路网络

    // 未连接信号默认值处理 ...

endmodule