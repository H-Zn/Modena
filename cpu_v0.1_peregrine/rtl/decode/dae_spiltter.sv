// dae_splitter.sv
import cpu_pkg::*;

module dae_splitter (
    input  micro_op_t micro_op_i,
    input  logic      stall_i,
    input  logic [31:0] pc_i,        // 新增：PC传递
    output logic      maq_wr_o,
    output maq_entry_t maq_data_o,
    output logic      eiq_wr_o,
    output eiq_entry_t eiq_data_o,
    output logic      dual_issue_o
);

    // 指令分类
    logic is_load_store, is_execute, is_atomic;
    assign is_load_store = micro_op_i.mem_read | micro_op_i.mem_write;
    assign is_atomic     = micro_op_i.is_atomic;
    assign is_execute    = ~is_load_store | is_atomic; // 原子操作也需进入执行队列进行锁存/计算

    // 写使能
    always_comb begin
        if (stall_i) begin
            maq_wr_o = 1'b0;
            eiq_wr_o = 1'b0;
        end else begin
            maq_wr_o = is_load_store & ~is_atomic;
            eiq_wr_o = is_execute;
        end
    end

    assign dual_issue_o = 1'b0; // 预留双发射

    // MAQ数据组装
    always_comb begin
        maq_data_o = '0;
        maq_data_o.valid       = is_load_store & ~stall_i;
        maq_data_o.is_load     = micro_op_i.mem_read;
        maq_data_o.is_atomic   = micro_op_i.is_atomic;
        maq_data_o.atomic_op   = micro_op_i.atomic_op;
        maq_data_o.mem_width   = micro_op_i.mem_width;
        maq_data_o.mem_sign_ext= micro_op_i.mem_sign_ext;
        maq_data_o.mem_aq      = micro_op_i.mem_aq;
        maq_data_o.mem_rl      = micro_op_i.mem_rl;
        maq_data_o.rd_addr     = micro_op_i.rd_addr;
        maq_data_o.rd_wen      = micro_op_i.rd_wen;
    end

    // EIQ数据组装
    always_comb begin
        eiq_data_o = '0;
        eiq_data_o.valid       = is_execute & ~stall_i;
        eiq_data_o.alu_op      = micro_op_i.alu_op;
        eiq_data_o.alu_src1_sel= micro_op_i.alu_src1_sel;
        eiq_data_o.alu_src2_sel= micro_op_i.alu_src2_sel;
        eiq_data_o.branch_type = micro_op_i.branch_type;
        eiq_data_o.is_branch   = micro_op_i.is_branch;
        eiq_data_o.is_jal      = micro_op_i.is_jal;
        eiq_data_o.is_jalr     = micro_op_i.is_jalr;
        eiq_data_o.is_mul_div  = micro_op_i.is_mul_div;
        eiq_data_o.mul_div_op  = micro_op_i.mul_div_op;
        eiq_data_o.is_csr      = micro_op_i.is_csr;
        eiq_data_o.csr_op      = micro_op_i.csr_op;
        eiq_data_o.csr_addr    = micro_op_i.csr_addr;
        eiq_data_o.is_ecall    = micro_op_i.is_ecall;
        eiq_data_o.is_ebreak   = micro_op_i.is_ebreak;
        eiq_data_o.is_mret     = micro_op_i.is_mret;
        eiq_data_o.is_sret     = micro_op_i.is_sret;
        eiq_data_o.is_wfi      = micro_op_i.is_wfi;
        eiq_data_o.is_fence    = micro_op_i.is_fence;
        eiq_data_o.rs1_ready   = 1'b0;
        eiq_data_o.rs2_ready   = 1'b0;
        eiq_data_o.rs1_data    = 32'h0;
        eiq_data_o.rs2_data    = 32'h0;
        eiq_data_o.rd_addr     = micro_op_i.rd_addr;
        eiq_data_o.rd_wen      = micro_op_i.rd_wen;
        eiq_data_o.imm         = micro_op_i.imm;
        eiq_data_o.pc          = pc_i;
    end

endmodule