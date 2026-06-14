// peregrine_top.sv
// Peregrine RISC-V Processor Top Level - FPGA Synthesizable Version
`timescale 1ns / 1ps
import cpu_pkg::*;

module peregrine_top #(
    parameter CORE_ID = 0,
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
    input  logic        clk_i,
    input  logic        rst_n_i,

    input  logic        irq_software_i,
    input  logic        irq_timer_i,
    input  logic        irq_external_i,

    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_awaddr,
    output logic [ 7:0] m_axi_awlen,
    output logic [ 2:0] m_axi_awsize,
    output logic [ 1:0] m_axi_awburst,

    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    output logic [31:0] m_axi_wdata,
    output logic [ 3:0] m_axi_wstrb,
    output logic        m_axi_wlast,

    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    input  logic [ 1:0] m_axi_bresp,

    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    output logic [31:0] m_axi_araddr,
    output logic [ 7:0] m_axi_arlen,
    output logic [ 2:0] m_axi_arsize,
    output logic [ 1:0] m_axi_arburst,

    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,
    input  logic [31:0] m_axi_rdata,
    input  logic        m_axi_rlast,
    input  logic [ 1:0] m_axi_rresp,

    input  logic        jtag_tck,
    input  logic        jtag_tms,
    input  logic        jtag_tdi,
    output logic        jtag_tdo,

    // UART
    output logic        uart_tx,
    input  logic        uart_rx,

    // LED
    output logic [1:0]  led
);

    logic clk;
    logic rst_n;

    clk_rst_manager clk_rst_manager_inst (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .clk_o        (clk),
        .rst_sync_n_o (rst_n),
        .pll_locked_o ()
    );

    // ============================================================
    // Pipeline Register Declarations
    // ============================================================

    // IF/ID
    logic [31:0] id_pc;
    logic [31:0] id_inst;
    logic        id_pred_dir;
    logic [31:0] id_pred_target;
    logic        id_fold_en;

    // ID/EX1
    micro_op_t   ex1_micro_op;
    logic [31:0] ex1_pc;
    logic        ex1_illegal;

    // EX1/EX2
    logic [31:0] ex2_addr;
    logic [31:0] ex2_opa;
    logic [31:0] ex2_opb;
    logic [ 3:0] ex2_alu_op;
    logic [ 2:0] ex2_branch_type;
    logic        ex2_is_branch;
    logic        ex2_is_jal;
    logic        ex2_is_jalr;
    logic [31:0] ex2_pc;
    logic [31:0] ex2_imm;
    logic [ 4:0] ex2_rd_addr;
    logic        ex2_rd_wen;
    logic        ex2_mem_read;
    logic        ex2_mem_write;
    logic [ 1:0] ex2_mem_width;
    logic        ex2_mem_sign_ext;
    logic [ 3:0] ex2_wmask;
    logic        ex2_is_mul_div;
    logic [ 2:0] ex2_mul_div_op;

    // EX2 results
    logic [31:0] ex2_result;
    logic [31:0] alu_result, mul_div_result;
    logic        mul_div_busy, mul_div_valid;

    // EX2/EX3
    logic [31:0] ex3_result;
    logic [31:0] ex3_store_data;
    logic [ 4:0] ex3_rd_addr;
    logic        ex3_rd_wen;
    logic        ex3_exception;
    exc_code_t   ex3_exc_code;
    logic [31:0] ex3_pc;
    logic        ex3_mem_read;
    logic        ex3_mem_write;
    logic [ 1:0] ex3_mem_width;
    logic        ex3_mem_sign_ext;
    logic [ 3:0] ex3_wmask;
    logic [31:0] ex3_addr;

    // ============================================================
    // Stall & Flush
    // ============================================================
    logic stall_if, stall_id, stall_ex1;
    logic flush_if, flush_id, flush_ex1, flush_ex2;
    logic pc_redirect_valid;
    logic [31:0] pc_redirect_target;

    // SRB signals
    logic        srb_alloc_en, srb_alloc_full;
    logic [ 4:0] srb_alloc_idx;
    logic        srb_result_wr_en;
    logic [ 4:0] srb_result_idx;
    logic [31:0] srb_result_data;
    logic        srb_result_exception;
    exc_code_t   srb_result_exc_code;
    logic        srb_commit_valid;
    logic [ 4:0] srb_commit_rd_addr;
    logic [31:0] srb_commit_rd_data;
    logic        srb_commit_rd_wen;
    logic        srb_store_commit;
    logic [ 2:0] srb_store_commit_idx;
    logic        srb_exc_req;
    logic [31:0] srb_exc_pc;
    exc_code_t   srb_exc_code;
    logic        srb_stall_wb;
    logic        srb_instret_event;

    logic dep_stall, maq_full_stall, eiq_full_stall, srb_stall;
    logic icache_miss_stall, dcache_miss_stall;

    assign stall_if  = icache_miss_stall | stall_id;
    assign stall_id  = dep_stall | maq_full_stall | eiq_full_stall | srb_stall;
    assign stall_ex1 = dcache_miss_stall;

    // ============================================================
    // Frontend: PC, Predictor, BTB, RAS, I-Cache/ITCM
    // ============================================================
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
        .flush        (pc_redirect_valid),
        .flush_target (pc_redirect_target),
        .stall        (stall_if),
        .pc           (pc)
    );

    logic [7:0] pred_conf;
    logic       update_pred_valid;
    logic [31:0] update_pred_pc;
    logic        update_pred_taken;

    perceptron_predictor perceptron_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .pc_query     (pc),
        .pred_dir     (pred_dir),
        .pred_conf    (pred_conf),
        .update_valid (update_pred_valid),
        .update_pc    (update_pred_pc),
        .update_taken (update_pred_taken)
    );

    logic        btb_hit;
    logic [31:0] btb_target;
    logic        btb_update_valid;
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

    logic        ras_push, ras_pop;
    logic [31:0] ras_push_addr, ras_pred_target;
    logic        ras_empty;

    ras ras_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .push_valid  (ras_push),
        .push_addr   (ras_push_addr),
        .pop_valid   (ras_pop),
        .pred_target (ras_pred_target),
        .empty       (ras_empty)
    );

    logic btb_is_branch;
    assign btb_is_branch = btb_hit;

    branch_folder branch_folder_inst (
        .is_branch   (btb_is_branch),
        .pred_dir    (pred_dir),
        .conf        (pred_conf),
        .btb_hit     (btb_hit),
        .btb_target  (btb_target),
        .fold_en     (fold_en),
        .fold_target (pred_target)
    );

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
        .axi_arvalid  (m_axi_arvalid),
        .axi_arready  (m_axi_arready),
        .axi_araddr   (m_axi_araddr),
        .axi_arlen    (m_axi_arlen),
        .axi_arsize   (m_axi_arsize),
        .axi_arburst  (m_axi_arburst),
        .axi_rvalid   (m_axi_rvalid),
        .axi_rready   (m_axi_rready),
        .axi_rdata    (m_axi_rdata),
        .axi_rlast    (m_axi_rlast)
    );

    logic        itcm_sel, itcm_rsp_valid;
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

    logic [31:0] if_raw_inst;
    logic        if_inst_valid;
    assign if_raw_inst  = itcm_sel ? itcm_rdata : icache_rdata;
    assign if_inst_valid = itcm_rsp_valid | icache_rsp_valid;

    logic [31:0] aligned_inst;
    logic        align_valid;

    inst_aligner inst_aligner_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .raw_data   (if_raw_inst),
        .pc_low     (pc[1:0]),
        .valid_in   (if_inst_valid),
        .ready      (),
        .inst_out   (aligned_inst),
        .valid_out  (align_valid)
    );

    // IF/ID Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_pc          <= 32'h0;
            id_inst        <= 32'h0;
            id_pred_dir    <= 1'b0;
            id_pred_target <= 32'h0;
            id_fold_en     <= 1'b0;
        end else if (!stall_id) begin
            if (flush_id) begin
                id_pc          <= 32'h0;
                id_inst        <= 32'h0;
                id_pred_dir    <= 1'b0;
                id_pred_target <= 32'h0;
                id_fold_en     <= 1'b0;
            end else if (align_valid) begin
                id_pc          <= pc;
                id_inst        <= aligned_inst;
                id_pred_dir    <= pred_dir;
                id_pred_target <= pred_target;
                id_fold_en     <= fold_en;
            end
        end
    end

    // ============================================================
    // Decode & Dispatch
    // ============================================================
    micro_op_t dec_micro_op;
    logic      dec_illegal;

    decoder decoder_inst (
        .inst_i      (id_inst),
        .pc_i        (id_pc),
        .micro_op_o  (dec_micro_op),
        .illegal_o   (dec_illegal)
    );

    logic [4:0] srb_alloc_rd_addr;
    logic       srb_alloc_rd_wen;
    logic [31:0] srb_alloc_pc;

    dep_checker dep_checker_inst (
        .rs1_addr_i     (dec_micro_op.rs1_addr),
        .rs2_addr_i     (dec_micro_op.rs2_addr),
        .rs1_used_i     (dec_micro_op.rs1_used),
        .rs2_used_i     (dec_micro_op.rs2_used),
        .rd_ex1_i       (ex1_micro_op.rd_addr),
        .rd_wen_ex1_i   (ex1_micro_op.rd_wen),
        .rd_ex2_i       (ex2_rd_addr),
        .rd_wen_ex2_i   (ex2_rd_wen),
        .rd_ex3_i       (ex3_rd_addr),
        .rd_wen_ex3_i   (ex3_rd_wen),
        .load_miss_i    (dcache_miss_stall),
        .mul_div_busy_i (mul_div_busy),
        .stall_o        (dep_stall)
    );

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

    // ID/EX1 Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex1_micro_op <= '0;
            ex1_pc       <= 32'h0;
            ex1_illegal  <= 1'b0;
        end else if (!stall_ex1) begin
            if (flush_ex1) begin
                ex1_micro_op <= '0;
                ex1_pc       <= 32'h0;
                ex1_illegal  <= 1'b0;
            end else begin
                ex1_micro_op <= dec_micro_op;
                ex1_pc       <= id_pc;
                ex1_illegal  <= dec_illegal;
            end
        end
    end

    // ============================================================
    // EX1: MAQ/EIQ/Regfile/AGU/Bypass
    // ============================================================
    logic maq_full, eiq_full;
    logic maq_rd_en, eiq_rd_en;
    maq_entry_t maq_rd_data;
    eiq_entry_t eiq_rd_data;

    maq maq_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush_i    (flush_ex1),
        .wr_en_i    (maq_wr),
        .wr_data_i  (maq_wr_data),
        .full_o     (maq_full),
        .rd_en_i    (maq_rd_en),
        .rd_data_o  (maq_rd_data),
        .empty_o    (),
        .stall_req_o(maq_full_stall)
    );

    eiq eiq_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush_i    (flush_ex1),
        .wr_en_i    (eiq_wr),
        .wr_data_i  (eiq_wr_data),
        .full_o     (eiq_full),
        .rd_en_i    (eiq_rd_en),
        .rd_data_o  (eiq_rd_data),
        .empty_o    (),
        .stall_req_o(eiq_full_stall)
    );

    // Register File
    logic [31:0] rf_rs1_data, rf_rs2_data;

    regfile regfile_inst (
        .clk       (clk),
        .rs1_addr_i(ex1_micro_op.rs1_addr),
        .rs1_data_o(rf_rs1_data),
        .rs2_addr_i(ex1_micro_op.rs2_addr),
        .rs2_data_o(rf_rs2_data),
        .wr_en_i   (srb_commit_valid & srb_commit_rd_wen),
        .rd_addr_i (srb_commit_rd_addr),
        .rd_data_i (srb_commit_rd_data)
    );

    // Bypass Network
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
        .wb_rd_i      (srb_commit_rd_addr),
        .wb_wen_i     (srb_commit_valid & srb_commit_rd_wen),
        .wb_result_i  (srb_commit_rd_data),
        .op1_o        (bypass_opa),
        .op2_o        (bypass_opb)
    );

    // AGU
    logic [31:0] agu_addr;
    logic        agu_misaligned;

    agu agu_inst (
        .base_i      (bypass_opa),
        .offset_i    (ex1_micro_op.imm),
        .addr_o      (agu_addr),
        .misaligned_o(agu_misaligned)
    );

    // EX1/EX2 Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex2_addr         <= 32'h0;
            ex2_opa          <= 32'h0;
            ex2_opb          <= 32'h0;
            ex2_alu_op       <= 4'h0;
            ex2_branch_type  <= 3'h0;
            ex2_is_branch    <= 1'b0;
            ex2_is_jal       <= 1'b0;
            ex2_is_jalr      <= 1'b0;
            ex2_pc           <= 32'h0;
            ex2_imm          <= 32'h0;
            ex2_rd_addr      <= 5'h0;
            ex2_rd_wen       <= 1'b0;
            ex2_mem_read     <= 1'b0;
            ex2_mem_write    <= 1'b0;
            ex2_mem_width    <= 2'h0;
            ex2_mem_sign_ext <= 1'b0;
            ex2_wmask        <= 4'h0;
            ex2_is_mul_div   <= 1'b0;
            ex2_mul_div_op   <= 3'h0;
        end else if (!stall_ex1) begin
            if (flush_ex1) begin
                ex2_addr         <= 32'h0;
                ex2_opa          <= 32'h0;
                ex2_opb          <= 32'h0;
                ex2_alu_op       <= 4'h0;
                ex2_branch_type  <= 3'h0;
                ex2_is_branch    <= 1'b0;
                ex2_is_jal       <= 1'b0;
                ex2_is_jalr      <= 1'b0;
                ex2_pc           <= 32'h0;
                ex2_imm          <= 32'h0;
                ex2_rd_addr      <= 5'h0;
                ex2_rd_wen       <= 1'b0;
                ex2_mem_read     <= 1'b0;
                ex2_mem_write    <= 1'b0;
                ex2_mem_width    <= 2'h0;
                ex2_mem_sign_ext <= 1'b0;
                ex2_wmask        <= 4'h0;
                ex2_is_mul_div   <= 1'b0;
                ex2_mul_div_op   <= 3'h0;
            end else begin
                ex2_addr         <= agu_addr;
                ex2_opa          <= bypass_opa;
                ex2_opb          <= bypass_opb;
                ex2_alu_op       <= ex1_micro_op.alu_op;
                ex2_branch_type  <= ex1_micro_op.branch_type;
                ex2_is_branch    <= ex1_micro_op.is_branch;
                ex2_is_jal       <= ex1_micro_op.is_jal;
                ex2_is_jalr      <= ex1_micro_op.is_jalr;
                ex2_pc           <= ex1_pc;
                ex2_imm          <= ex1_micro_op.imm;
                ex2_rd_addr      <= ex1_micro_op.rd_addr;
                ex2_rd_wen       <= ex1_micro_op.rd_wen;
                ex2_mem_read     <= ex1_micro_op.mem_read;
                ex2_mem_write    <= ex1_micro_op.mem_write;
                ex2_mem_width    <= ex1_micro_op.mem_width;
                ex2_mem_sign_ext <= ex1_micro_op.mem_sign_ext;
                ex2_wmask        <= 4'hF;
                ex2_is_mul_div   <= ex1_micro_op.is_mul_div;
                ex2_mul_div_op   <= ex1_micro_op.mul_div_op;
            end
        end
    end

    // ============================================================
    // EX2: Execution Islands
    // ============================================================

    alu_island alu_inst (
        .alu_op_i (ex2_alu_op),
        .opa_i    (ex2_opa),
        .opb_i    (ex2_opb),
        .result_o (alu_result)
    );

    if (M_EXT_EN) begin : gen_mul_div
        mul_div_island mul_div_inst (
            .clk           (clk),
            .rst_n         (rst_n),
            .flush_i       (flush_ex2),
            .valid_i       (ex2_is_mul_div),
            .mul_div_op_i  (ex2_mul_div_op),
            .opa_i         (ex2_opa),
            .opb_i         (ex2_opb),
            .busy_o        (mul_div_busy),
            .result_o      (mul_div_result),
            .result_valid_o(mul_div_valid)
        );
    end else begin : gen_no_mul_div
        assign mul_div_busy   = 1'b0;
        assign mul_div_result = 32'h0;
        assign mul_div_valid  = 1'b0;
    end

    logic        bru_flush, bru_mispred;
    logic [31:0] bru_flush_target;
    logic        bru_actual_taken;

    bru_island bru_inst (
        .branch_type_i  (ex2_branch_type),
        .opa_i          (ex2_opa),
        .opb_i          (ex2_opb),
        .pc_i           (ex2_pc),
        .imm_i          (ex2_imm),
        .pred_dir_i     (id_pred_dir),
        .flush_o        (bru_flush),
        .flush_target_o (bru_flush_target),
        .actual_taken_o (bru_actual_taken),
        .mispredict_o   (bru_mispred)
    );

    assign ex2_result = ex2_is_mul_div ? mul_div_result : alu_result;

    // EX2/EX3 Pipeline Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex3_result       <= 32'h0;
            ex3_store_data   <= 32'h0;
            ex3_rd_addr      <= 5'h0;
            ex3_rd_wen       <= 1'b0;
            ex3_exception    <= 1'b0;
            ex3_exc_code     <= exc_code_t'(0);
            ex3_pc           <= 32'h0;
            ex3_mem_read     <= 1'b0;
            ex3_mem_write    <= 1'b0;
            ex3_mem_width    <= 2'h0;
            ex3_mem_sign_ext <= 1'b0;
            ex3_wmask        <= 4'h0;
            ex3_addr         <= 32'h0;
        end else begin
            if (flush_ex2) begin
                ex3_result       <= 32'h0;
                ex3_store_data   <= 32'h0;
                ex3_rd_addr      <= 5'h0;
                ex3_rd_wen       <= 1'b0;
                ex3_exception    <= 1'b0;
                ex3_exc_code     <= exc_code_t'(0);
                ex3_pc           <= 32'h0;
                ex3_mem_read     <= 1'b0;
                ex3_mem_write    <= 1'b0;
                ex3_mem_width    <= 2'h0;
                ex3_mem_sign_ext <= 1'b0;
                ex3_wmask        <= 4'h0;
                ex3_addr         <= 32'h0;
            end else begin
                ex3_result       <= ex2_result;
                ex3_store_data   <= ex2_opb;
                ex3_rd_addr      <= ex2_rd_addr;
                ex3_rd_wen       <= ex2_rd_wen;
                ex3_exception    <= 1'b0;
                ex3_exc_code     <= exc_code_t'(0);
                ex3_pc           <= ex2_pc;
                ex3_mem_read     <= ex2_mem_read;
                ex3_mem_write    <= ex2_mem_write;
                ex3_mem_width    <= ex2_mem_width;
                ex3_mem_sign_ext <= ex2_mem_sign_ext;
                ex3_wmask        <= ex2_wmask;
                ex3_addr         <= ex2_addr;
            end
        end
    end

    // ============================================================
    // Memory Subsystem: D-Cache, MSHR, Store Buffer, Writeback
    // ============================================================
    logic        dcache_rsp_valid, dcache_miss;
    logic [31:0] dcache_rdata;
    logic        mshr_alloc_valid, mshr_alloc_ready;
    logic [31:0] mshr_alloc_addr;
    logic        mshr_alloc_is_write;
    logic [ 1:0] mshr_alloc_id;

    logic        mshr_fill_valid;
    logic [ 1:0] mshr_fill_id;
    logic [31:0] mshr_fill_addr;
    logic [31:0] mshr_fill_data;
    logic        mshr_fill_last;

    logic        dcache_wb_req_valid;
    logic [31:0] dcache_wb_req_addr;
    logic [31:0] dcache_wb_req_data;
    logic [ 3:0] dcache_wb_req_mask;
    logic        dcache_wb_req_ready;

    dcache #(16*1024, 32, 4) dcache_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush_i           (flush_ex2),
        .req_valid_i       (ex3_mem_read | ex3_mem_write),
        .req_type_i        (ex3_mem_write ? MEM_REQ_STORE : MEM_REQ_LOAD),
        .req_addr_i        (ex3_addr),
        .req_wdata_i       (ex3_store_data),
        .req_wmask_i       (ex3_wmask),
        .req_is_atomic_i   (1'b0),
        .req_atomic_op_i   ('0),
        .rsp_valid_o       (dcache_rsp_valid),
        .rsp_rdata_o       (dcache_rdata),
        .rsp_miss_o        (dcache_miss),
        .mshr_alloc_valid_o(mshr_alloc_valid),
        .mshr_alloc_addr_o (mshr_alloc_addr),
        .mshr_alloc_is_write_o(mshr_alloc_is_write),
        .mshr_alloc_ready_i(mshr_alloc_ready),
        .mshr_alloc_id_i   (mshr_alloc_id),
        .mshr_fill_valid_i (mshr_fill_valid),
        .mshr_fill_id_i    (mshr_fill_id),
        .mshr_fill_addr_i  (mshr_fill_addr),
        .mshr_fill_data_i  (mshr_fill_data),
        .mshr_fill_last_i  (mshr_fill_last),
        .wb_req_valid_o    (dcache_wb_req_valid),
        .wb_req_addr_o     (dcache_wb_req_addr),
        .wb_req_data_o     (dcache_wb_req_data),
        .wb_req_mask_o     (dcache_wb_req_mask),
        .wb_req_ready_i    (dcache_wb_req_ready)
    );

    logic        mshr_fill_req_valid;
    logic [31:0] mshr_fill_req_addr;
    logic        mshr_fill_req_is_write;
    logic        mshr_fill_req_ready;
    logic        mshr_fill_data_valid;
    logic [31:0] mshr_fill_data_in;
    logic        mshr_fill_data_last;
    logic        mshr_fill_done_valid;
    logic [ 1:0] mshr_fill_done_id;

    mshr #(4) mshr_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush_i           (flush_ex2),
        .alloc_valid_i     (mshr_alloc_valid),
        .alloc_addr_i      (mshr_alloc_addr),
        .alloc_is_write_i  (mshr_alloc_is_write),
        .alloc_ready_o     (mshr_alloc_ready),
        .alloc_id_o        (mshr_alloc_id),
        .fill_req_valid_o  (mshr_fill_req_valid),
        .fill_req_addr_o   (mshr_fill_req_addr),
        .fill_req_is_write_o(mshr_fill_req_is_write),
        .fill_req_ready_i  (mshr_fill_req_ready),
        .fill_data_valid_i (mshr_fill_data_valid),
        .fill_data_i       (mshr_fill_data_in),
        .fill_data_last_i  (mshr_fill_data_last),
        .fill_done_valid_o (mshr_fill_done_valid),
        .fill_done_id_o    (mshr_fill_done_id)
    );

    assign mshr_fill_valid = mshr_fill_done_valid;
    assign mshr_fill_id    = mshr_fill_done_id;
    assign mshr_fill_addr  = mshr_fill_req_addr;
    assign mshr_fill_data  = mshr_fill_data_in;
    assign mshr_fill_last  = mshr_fill_data_last;

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
        .load_addr_i        (ex3_addr),
        .load_width_i       (ex3_mem_width),
        .forward_hit_o      (stb_forward_hit),
        .forward_data_o     (stb_forward_data),
        .wb_rd_en_i         (stb_wb_rd_en),
        .wb_rd_data_o       (stb_wb_rd_data),
        .empty_o            (stb_empty),
        .clear_uncommitted_i(flush_ex2)
    );

    logic        wb_dcache_wr_req;
    logic [31:0] wb_dcache_wr_addr;
    logic [31:0] wb_dcache_wr_data;
    logic [ 3:0] wb_dcache_wr_mask;
    logic        wb_dcache_wr_gnt;
    logic        wb_dcache_wr_done;
    logic        wb_dcache_wr_miss;
    logic        wb_mshr_alloc_valid;
    logic [31:0] wb_mshr_alloc_addr;
    logic        wb_mshr_alloc_ready;
    logic        wb_mshr_fill_done;

    writeback_sync writeback_sync_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .stb_rd_en_o      (stb_wb_rd_en),
        .stb_rd_data_i    (stb_wb_rd_data),
        .stb_empty_i      (stb_empty),
        .dcache_wr_req_o  (wb_dcache_wr_req),
        .dcache_wr_addr_o (wb_dcache_wr_addr),
        .dcache_wr_data_o (wb_dcache_wr_data),
        .dcache_wr_mask_o (wb_dcache_wr_mask),
        .dcache_wr_gnt_i  (wb_dcache_wr_gnt),
        .dcache_wr_done_i (wb_dcache_wr_done),
        .dcache_wr_miss_i (wb_dcache_wr_miss),
        .mshr_alloc_valid_o(wb_mshr_alloc_valid),
        .mshr_alloc_addr_o(wb_mshr_alloc_addr),
        .mshr_alloc_ready_i(wb_mshr_alloc_ready),
        .mshr_fill_done_i (wb_mshr_fill_done)
    );

    assign dcache_wb_req_ready = 1'b1;
    assign wb_dcache_wr_gnt    = 1'b1;
    assign wb_dcache_wr_done   = 1'b1;
    assign wb_dcache_wr_miss   = 1'b0;
    assign wb_mshr_alloc_ready = 1'b1;
    assign wb_mshr_fill_done   = 1'b1;

    // ============================================================
    // Commit: SRB
    // ============================================================
    assign srb_alloc_en     = !stall_ex1 && !flush_ex1 && (ex1_micro_op.rd_wen || ex1_micro_op.mem_write);
    assign srb_alloc_rd_addr = ex1_micro_op.rd_addr;
    assign srb_alloc_rd_wen  = ex1_micro_op.rd_wen;
    assign srb_alloc_pc      = ex1_pc;

    srb #(16) srb_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush_i           (flush_ex2),
        .alloc_en_i        (srb_alloc_en),
        .alloc_rd_addr_i   (ex1_micro_op.rd_addr),
        .alloc_rd_wen_i    (ex1_micro_op.rd_wen),
        .alloc_pc_i        (ex1_pc),
        .alloc_idx_o       (srb_alloc_idx),
        .alloc_full_o      (srb_alloc_full),
        .result_wr_en_i    (srb_result_wr_en),
        .result_idx_i      (srb_result_idx),
        .result_data_i     (srb_result_data),
        .result_exception_i(srb_result_exception),
        .result_exc_code_i (srb_result_exc_code),
        .commit_valid_o    (srb_commit_valid),
        .commit_rd_addr_o  (srb_commit_rd_addr),
        .commit_rd_data_o  (srb_commit_rd_data),
        .commit_rd_wen_o   (srb_commit_rd_wen),
        .store_commit_o    (srb_store_commit),
        .store_commit_idx_o(srb_store_commit_idx),
        .exc_req_o         (srb_exc_req),
        .exc_pc_o          (srb_exc_pc),
        .exc_code_o        (srb_exc_code),
        .stall_wb_o        (srb_stall_wb),
        .instret_event_o   (srb_instret_event)
    );

    assign srb_result_wr_en    = 1'b0;
    assign srb_result_idx      = 5'h0;
    assign srb_result_data     = 32'h0;
    assign srb_result_exception = 1'b0;
    assign srb_result_exc_code  = exc_code_t'(0);

    // ============================================================
    // Control: Flush, Exception, PMU
    // ============================================================
    logic fencei_req;
    assign fencei_req = dec_micro_op.is_fence && (id_inst[14:12] == 3'b001);

    flush_controller flush_ctrl_inst (
        .clk                (clk),
        .rst_n              (rst_n),
        .exc_req_i          (srb_exc_req),
        .exc_target_i       (srb_exc_pc),
        .mispred_req_i      (bru_flush),
        .mispred_target_i   (bru_flush_target),
        .fencei_req_i       (fencei_req),
        .debug_req_i        (1'b0),
        .flush_if_o         (flush_if),
        .flush_id_o         (flush_id),
        .flush_ex1_o        (flush_ex1),
        .flush_ex2_o        (flush_ex2),
        .pc_redirect_valid_o(pc_redirect_valid),
        .pc_redirect_target_o(pc_redirect_target),
        .flush_event_o      (),
        .mispred_event_o    ()
    );

    exception_handler exc_inst (
        .clk               (clk),
        .rst_n             (rst_n),
        .id_illegal_i      (dec_illegal),
        .id_pc_i           (id_pc),
        .id_inst_i         (id_inst),
        .ex1_misaligned_i  (agu_misaligned),
        .ex1_pc_i          (ex1_pc),
        .ex1_addr_i        (agu_addr),
        .ex2_ecall_i       (ex1_micro_op.is_ecall),
        .ex2_ebreak_i      (ex1_micro_op.is_ebreak),
        .ex2_div_zero_i    (1'b0),
        .ex2_pc_i          (ex2_pc),
        .mem_access_fault_i(1'b0),
        .mem_page_fault_i  (1'b0),
        .mem_pc_i          (ex3_pc),
        .mem_addr_i        (ex3_addr),
        .ext_irq_i         (irq_external_i),
        .timer_irq_i       (irq_timer_i),
        .soft_irq_i        (irq_software_i),
        .csr_wr_en_i       (dec_micro_op.is_csr),
        .csr_addr_i        (dec_micro_op.csr_addr),
        .csr_wdata_i       (bypass_opa),
        .csr_rdata_o       (),
        .exc_req_o         (),
        .exc_target_o      (),
        .exception_taken_o (),
        .interrupt_taken_o ()
    );

    if (PMU_EN) begin : gen_pmu
        perf_counters perf_inst (
            .clk                     (clk),
            .rst_n                   (rst_n),
            .cycle_event_i           (1'b1),
            .instret_event_i         (srb_instret_event),
            .branch_mispred_event_i  (bru_mispred),
            .data_stall_event_i      (dep_stall),
            .control_stall_event_i   (flush_if),
            .icache_miss_event_i     (icache_miss_stall),
            .dcache_miss_event_i     (dcache_miss),
            .load_use_stall_event_i  (1'b0),
            .csr_rd_en_i             (1'b0),
            .csr_rd_addr_i           (12'b0),
            .csr_rd_data_o           (),
            .cnt_sel_i               (3'b0),
            .event_sel_i             (3'b0),
            .cnt_wr_en_i             (1'b0)
        );
    end

    // ============================================================
    // Predictor Update Connections
    // ============================================================
    assign itcm_sel = (pc >= 32'h0000_0000) && (pc < 32'h0000_1000);

    assign update_pred_valid = bru_flush;
    assign update_pred_pc    = ex2_pc;
    assign update_pred_taken = bru_actual_taken;

    assign btb_update_valid  = (ex2_is_jal | ex2_is_jalr | (ex2_is_branch & bru_actual_taken));
    assign btb_update_pc     = ex2_pc;
    assign btb_update_target = ex2_result;

    assign ras_push      = ex1_micro_op.is_call;
    assign ras_push_addr = ex1_pc + 32'd4;
    assign ras_pop       = ex1_micro_op.is_ret;

    assign dcache_miss_stall = dcache_miss & (ex3_mem_read | ex3_mem_write);

    assign jtag_tdo = 1'b0;

    // ============================================================
    // UART TX - 发送 "Hello" 测试
    // ============================================================
    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;

    uart_tx #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115200)
    ) uart_tx_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_data  (uart_tx_data),
        .tx_valid (uart_tx_valid),
        .tx_ready (uart_tx_ready),
        .tx_pin   (uart_tx)
    );

    // Hello 状态机
    typedef enum logic [3:0] {
        S_IDLE, S_H, S_e, S_l1, S_l2, S_o, S_NL, S_DONE
    } hello_state_t;

    hello_state_t hello_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hello_state  <= S_IDLE;
            uart_tx_valid <= 1'b0;
            uart_tx_data  <= 8'h0;
        end else begin
            uart_tx_valid <= 1'b0;
            if (uart_tx_ready) begin
                case (hello_state)
                    S_IDLE: begin
                        uart_tx_valid <= 1'b1;
                        uart_tx_data  <= "H";
                        hello_state   <= S_e;
                    end
                    S_e: begin
                        uart_tx_valid <= 1'b1;
                        uart_tx_data  <= "e";
                        hello_state   <= S_l1;
                    end
                    S_l1: begin
                        uart_tx_valid <= 1'b1;
                        uart_tx_data  <= "l";
                        hello_state   <= S_l2;
                    end
                    S_l2: begin
                        uart_tx_valid <= 1'b1;
                        uart_tx_data  <= "l";
                        hello_state   <= S_o;
                    end
                    S_o: begin
                        uart_tx_valid <= 1'b1;
                        uart_tx_data  <= "o";
                        hello_state   <= S_NL;
                    end
                    S_NL: begin
                        uart_tx_valid <= 1'b1;
                        uart_tx_data  <= 8'h0A;
                        hello_state   <= S_DONE;
                    end
                    S_DONE: begin
                        hello_state <= S_IDLE;
                    end
                    default: hello_state <= S_IDLE;
                endcase
            end
        end
    end

    assign led[0] = ~rst_n;
    assign led[1] = (hello_state != S_IDLE);

endmodule
