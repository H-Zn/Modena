// ============================================================
// FILE: include/cpu_pkg.sv
// DESCRIPTION: Peregrine Processor Shared Package
// Contains common types, structs, and enums used across all modules.
// ============================================================

package cpu_pkg;

    // ------------------- 异常/中断代码 (mcause/scause) -------------------
    typedef enum logic [3:0] {
        EXC_INST_MISALIGNED  = 4'd0,
        EXC_INST_ACCESS      = 4'd1,
        EXC_ILLEGAL_INST     = 4'd2,
        EXC_BREAKPOINT       = 4'd3,
        EXC_LOAD_MISALIGNED  = 4'd4,
        EXC_LOAD_ACCESS      = 4'd5,
        EXC_STORE_MISALIGNED = 4'd6,
        EXC_STORE_ACCESS     = 4'd7,
        EXC_ECALL_U          = 4'd8,
        EXC_ECALL_S          = 4'd9,
        EXC_ECALL_M          = 4'd11,
        EXC_INST_PAGE_FAULT  = 4'd12,
        EXC_LOAD_PAGE_FAULT  = 4'd13,
        EXC_STORE_PAGE_FAULT = 4'd15
    } exc_code_t;

    // ------------------- 冲刷源类型 -------------------
    typedef enum logic [1:0] {
        FLUSH_NONE      = 2'b00,
        FLUSH_EXCEPTION = 2'b01,
        FLUSH_MISPRED   = 2'b10,
        FLUSH_FENCEI    = 2'b11
    } flush_src_t;

    // ------------------- 性能计数器事件选择 -------------------
    typedef enum logic [2:0] {
        EVENT_CYCLE          = 3'b000,
        EVENT_INSTRET        = 3'b001,
        EVENT_BRANCH_MISPRED = 3'b010,
        EVENT_DATA_STALL     = 3'b011,
        EVENT_CTRL_STALL     = 3'b100,
        EVENT_ICACHE_MISS    = 3'b101,
        EVENT_DCACHE_MISS    = 3'b110,
        EVENT_LOAD_USE_STALL = 3'b111
    } pmu_event_t;

    // ------------------- 访存请求类型 -------------------
    typedef enum logic [1:0] {
        MEM_REQ_NONE   = 2'b00,
        MEM_REQ_LOAD   = 2'b01,
        MEM_REQ_STORE  = 2'b10,
        MEM_REQ_ATOMIC = 2'b11
    } mem_req_type_t;

    // ------------------- MSHR 条目状态 -------------------
    typedef enum logic [1:0] {
        MSHR_IDLE      = 2'b00,
        MSHR_PENDING   = 2'b01,
        MSHR_FILLING   = 2'b10,
        MSHR_WRITEBACK = 2'b11
    } mshr_state_t;

    // ------------------- AXI 突发类型 -------------------
    typedef enum logic [1:0] {
        AXI_FIXED = 2'b00,
        AXI_INCR  = 2'b01,
        AXI_WRAP  = 2'b10
    } axi_burst_t;

    // ------------------- AXI 响应类型 -------------------
    typedef enum logic [1:0] {
        AXI_OKAY   = 2'b00,
        AXI_EXOKAY = 2'b01,
        AXI_SLVERR = 2'b10,
        AXI_DECERR = 2'b11
    } axi_resp_t;

    // ------------------- 微码结构体 (micro_op_t) -------------------
    // 完整支持 RV32IMA_Zicsr_Zifencei_S 扩展
    typedef struct packed {
        // 基本指令标识
        logic [ 6:0] opcode;
        logic [ 2:0] funct3;
        logic [ 6:0] funct7;
        logic [11:0] csr_addr;       // Zicsr: CSR地址

        // 寄存器地址
        logic [ 4:0] rs1_addr;
        logic [ 4:0] rs2_addr;
        logic [ 4:0] rd_addr;
        logic        rs1_used;
        logic        rs2_used;
        logic        rd_wen;

        // 立即数
        logic [31:0] imm;

        // ALU控制
        logic [ 3:0] alu_op;          // 运算类型
        logic        alu_src1_sel;     // 0: rs1, 1: pc
        logic        alu_src2_sel;     // 0: rs2, 1: imm

        // 分支控制
        logic        is_branch;
        logic [ 2:0] branch_type;     // BEQ/BNE/BLT/BGE/BLTU/BGEU

        // 跳转控制
        logic        is_jal;
        logic        is_jalr;
        logic        is_call;          // 用于RAS压栈 (JAL rd=x1/x5)
        logic        is_ret;           // 用于RAS弹栈 (JALR rs1=x1/x5)

        // 访存控制
        logic        mem_read;
        logic        mem_write;
        logic [ 1:0] mem_width;        // 00:byte, 01:half, 10:word
        logic        mem_sign_ext;     // Load符号扩展
        logic        mem_aq;           // A扩展: Acquire
        logic        mem_rl;           // A扩展: Release

        // 原子操作 (A扩展)
        logic        is_atomic;
        logic [ 3:0] atomic_op;        // LR/SC/AMOSWAP/AMOADD/AMOXOR/AMOAND/AMOOR/AMOMIN/AMOMAX/AMOMINU/AMOMAXU

        // 乘除法 (M扩展)
        logic        is_mul_div;
        logic [ 2:0] mul_div_op;       // MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU

        // 系统指令
        logic        is_csr;            // Zicsr: CSR访问
        logic [ 1:0] csr_op;           // 00:NOP, 01:RW, 10:RS, 11:RC
        logic        is_ecall;
        logic        is_ebreak;
        logic        is_mret;
        logic        is_sret;
        logic        is_wfi;
        logic        is_fence;          // FENCE/FENCE.I

        // 异常标识
        logic        illegal;
    } micro_op_t;

    // ------------------- 访存地址队列条目 (MAQ Entry) -------------------
    typedef struct packed {
        logic        valid;
        logic [31:0] addr;             // EX1阶段填充
        logic [31:0] data;             // Store数据，EX2阶段填充
        logic [ 1:0] mem_width;
        logic        mem_sign_ext;
        logic        is_load;
        logic        is_atomic;
        logic [ 3:0] atomic_op;
        logic        mem_aq;
        logic        mem_rl;
        logic [ 4:0] rd_addr;
        logic        rd_wen;
    } maq_entry_t;

    // ------------------- 执行指令队列条目 (EIQ Entry) -------------------
    typedef struct packed {
        logic        valid;
        logic [ 3:0] alu_op;
        logic        alu_src1_sel;
        logic        alu_src2_sel;
        logic [ 2:0] branch_type;
        logic        is_branch;
        logic        is_jal;
        logic        is_jalr;
        logic        is_mul_div;
        logic [ 2:0] mul_div_op;
        logic        is_csr;
        logic [ 1:0] csr_op;
        logic [11:0] csr_addr;
        logic        is_ecall;
        logic        is_ebreak;
        logic        is_mret;
        logic        is_sret;
        logic        is_wfi;
        logic        is_fence;
        logic        rs1_ready;
        logic        rs2_ready;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [ 4:0] rd_addr;
        logic        rd_wen;
        logic [31:0] imm;
        logic [31:0] pc;
    } eiq_entry_t;

    // ------------------- 共享结果缓冲条目 (SRB Entry) -------------------
    typedef struct packed {
        logic        valid;
        logic [ 4:0] rd_addr;
        logic        rd_wen;
        logic [31:0] result;
        logic        ready;
        logic        exception;
        exc_code_t   exc_code;
        logic [31:0] pc;
    } srb_entry_t;

    // ------------------- 存储缓冲条目 (Store Buffer Entry) -------------------
    typedef struct packed {
        logic        valid;
        logic [31:0] addr;
        logic [31:0] data;
        logic [ 3:0] byte_mask;
        logic        committed;
    } stb_entry_t;

endpackage : cpu_pkg