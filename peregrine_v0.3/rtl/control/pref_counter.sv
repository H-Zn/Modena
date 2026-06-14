// perf_counters.sv
import cpu_pkg::*;

module perf_counters (
    input  logic        clk,
    input  logic        rst_n,

    // 事件输入
    input  logic        cycle_event_i,          // 每周期有效
    input  logic        instret_event_i,        // 指令提交
    input  logic        branch_mispred_event_i, // 分支误预测
    input  logic        data_stall_event_i,     // 数据冒险停顿
    input  logic        control_stall_event_i,  // 控制冲刷停顿
    input  logic        icache_miss_event_i,    // I$ miss
    input  logic        dcache_miss_event_i,    // D$ miss
    input  logic        load_use_stall_event_i, // Load-Use 停顿

    // CSR 访问接口 (读取计数器)
    input  logic        csr_rd_en_i,
    input  logic [11:0] csr_rd_addr_i,
    output logic [31:0] csr_rd_data_o,

    // 配置接口 (可选)
    input  logic [ 2:0] cnt_sel_i,     // 计数器选择 (用于事件配置)
    input  logic [ 2:0] event_sel_i,   // 事件选择
    input  logic        cnt_wr_en_i
);

    localparam NUM_COUNTERS = 8;
    logic [31:0] counters [0:NUM_COUNTERS-1];
    pmu_event_t event_sel [0:NUM_COUNTERS-1];

    // 默认事件分配
    initial begin
        event_sel[0] = EVENT_CYCLE;
        event_sel[1] = EVENT_INSTRET;
        event_sel[2] = EVENT_BRANCH_MISPRED;
        event_sel[3] = EVENT_DATA_STALL;
        event_sel[4] = EVENT_CTRL_STALL;
        event_sel[5] = EVENT_ICACHE_MISS;
        event_sel[6] = EVENT_DCACHE_MISS;
        event_sel[7] = EVENT_LOAD_USE_STALL;
    end

    // 事件映射
    function automatic logic get_event(pmu_event_t ev);
        case (ev)
            EVENT_CYCLE:          return cycle_event_i;
            EVENT_INSTRET:        return instret_event_i;
            EVENT_BRANCH_MISPRED: return branch_mispred_event_i;
            EVENT_DATA_STALL:     return data_stall_event_i;
            EVENT_CTRL_STALL:     return control_stall_event_i;
            EVENT_ICACHE_MISS:    return icache_miss_event_i;
            EVENT_DCACHE_MISS:    return dcache_miss_event_i;
            EVENT_LOAD_USE_STALL: return load_use_stall_event_i;
            default: return 1'b0;
        endcase
    endfunction

    // 计数器累加
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_COUNTERS; i++) counters[i] <= 32'h0;
        end else begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                if (get_event(event_sel[i]))
                    counters[i] <= counters[i] + 1'b1;
            end

            // 配置更新
            if (cnt_wr_en_i)
                event_sel[cnt_sel_i] <= pmu_event_t'(event_sel_i);
        end
    end

    // CSR 读
    // 计数器映射到自定义 CSR 地址: 0xCC0 ~ 0xCC7
    always_comb begin
        csr_rd_data_o = 32'h0;
        if (csr_rd_en_i) begin
            case (csr_rd_addr_i)
                12'hCC0: csr_rd_data_o = counters[0];
                12'hCC1: csr_rd_data_o = counters[1];
                12'hCC2: csr_rd_data_o = counters[2];
                12'hCC3: csr_rd_data_o = counters[3];
                12'hCC4: csr_rd_data_o = counters[4];
                12'hCC5: csr_rd_data_o = counters[5];
                12'hCC6: csr_rd_data_o = counters[6];
                12'hCC7: csr_rd_data_o = counters[7];
                default: csr_rd_data_o = 32'h0;
            endcase
        end
    end

endmodule