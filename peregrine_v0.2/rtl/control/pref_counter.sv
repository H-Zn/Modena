// perf_counters.sv
import cpu_pkg::*;

module perf_counters (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        cycle_event_i,
    input  logic        instret_event_i,
    input  logic        branch_mispred_event_i,
    input  logic        data_stall_event_i,
    input  logic        control_stall_event_i,
    input  logic        icache_miss_event_i,
    input  logic        dcache_miss_event_i,
    input  logic        load_use_stall_event_i,

    input  logic        csr_rd_en_i,
    input  logic [11:0] csr_rd_addr_i,
    output logic [31:0] csr_rd_data_o,

    input  logic [ 2:0] cnt_sel_i,
    input  logic [ 2:0] event_sel_i,
    input  logic        cnt_wr_en_i
);

    localparam NUM_COUNTERS = 8;
    logic [31:0] counters [0:NUM_COUNTERS-1];
    pmu_event_t event_mux [0:NUM_COUNTERS-1];
    logic [7:0] event_hit;

    always_comb begin
        for (int i = 0; i < NUM_COUNTERS; i++) begin
            case (event_mux[i])
                EVENT_CYCLE:          event_hit[i] = cycle_event_i;
                EVENT_INSTRET:        event_hit[i] = instret_event_i;
                EVENT_BRANCH_MISPRED: event_hit[i] = branch_mispred_event_i;
                EVENT_DATA_STALL:     event_hit[i] = data_stall_event_i;
                EVENT_CTRL_STALL:     event_hit[i] = control_stall_event_i;
                EVENT_ICACHE_MISS:    event_hit[i] = icache_miss_event_i;
                EVENT_DCACHE_MISS:    event_hit[i] = dcache_miss_event_i;
                EVENT_LOAD_USE_STALL: event_hit[i] = load_use_stall_event_i;
                default:              event_hit[i] = 1'b0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                counters[i] <= 32'h0;
                event_mux[i] <= pmu_event_t'(i);
            end
        end else begin
            for (int i = 0; i < NUM_COUNTERS; i++) begin
                if (event_hit[i])
                    counters[i] <= counters[i] + 1'b1;
            end
            if (cnt_wr_en_i && cnt_sel_i < 3'dNUM_COUNTERS)
                event_mux[cnt_sel_i] <= pmu_event_t'(event_sel_i);
        end
    end

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
