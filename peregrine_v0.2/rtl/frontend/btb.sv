module btb (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] pc_query,
    output logic        hit,
    output logic [31:0] target,

    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic [31:0] update_target
);

    localparam ENTRIES = 512;
    localparam WAYS    = 2;
    localparam INDEX_BITS = $clog2(ENTRIES / WAYS);

    typedef struct packed {
        logic [19:0] tag;
        logic [29:0] target;
        logic        valid;
    } btb_entry_t;

    btb_entry_t btb [0:ENTRIES/WAYS-1][0:WAYS-1];
    logic [WAYS-1:0] plru_bits [0:ENTRIES/WAYS-1];

    logic [INDEX_BITS-1:0] query_idx;
    logic [INDEX_BITS-1:0] update_idx;
    assign query_idx  = pc_query[INDEX_BITS+1:2];
    assign update_idx = update_pc[INDEX_BITS+1:2];

    logic [19:0] query_tag;
    assign query_tag = pc_query[31:12];

    always_comb begin
        hit = 1'b0;
        target = 32'h0;
        for (int i = 0; i < WAYS; i++) begin
            if (btb[query_idx][i].valid && btb[query_idx][i].tag == query_tag) begin
                hit = 1'b1;
                target = {btb[query_idx][i].target, 2'b00};
            end
        end
    end

    logic [19:0] upd_tag;
    logic        upd_hit;
    logic [1:0]  hit_way;
    logic [1:0]  replace_way;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRIES/WAYS; i++) begin
                plru_bits[i] <= '0;
                for (int j = 0; j < WAYS; j++)
                    btb[i][j] <= '{tag: 20'h0, target: 30'h0, valid: 1'b0};
            end
        end else if (update_valid) begin
            upd_tag = update_pc[31:12];
            upd_hit = 1'b0;
            hit_way = 2'b00;
            for (int i = 0; i < WAYS; i++) begin
                if (btb[update_idx][i].valid && btb[update_idx][i].tag == upd_tag) begin
                    upd_hit = 1'b1;
                    hit_way = i[1:0];
                end
            end
            if (upd_hit) begin
                btb[update_idx][hit_way].target <= update_target[31:2];
            end else begin
                replace_way = plru_bits[update_idx][0] ? 2'd1 : 2'd0;
                btb[update_idx][replace_way].tag    <= upd_tag;
                btb[update_idx][replace_way].target <= update_target[31:2];
                btb[update_idx][replace_way].valid  <= 1'b1;
                plru_bits[update_idx]               <= ~plru_bits[update_idx];
            end
        end
    end

endmodule
