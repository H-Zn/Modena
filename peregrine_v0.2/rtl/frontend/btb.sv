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

    btb_entry_t btb_ram [0:ENTRIES/WAYS-1][0:WAYS-1];
    logic [WAYS-1:0] plru_bits [0:ENTRIES/WAYS-1];

    logic [INDEX_BITS-1:0] query_idx;
    logic [INDEX_BITS-1:0] update_idx;
    assign query_idx  = pc_query[INDEX_BITS+1:2];
    assign update_idx = update_pc[INDEX_BITS+1:2];

    logic [19:0] query_tag;
    assign query_tag = pc_query[31:12];

    logic q_hit;
    logic [1:0] q_way;

    always_comb begin
        q_hit = 1'b0;
        q_way = 2'd0;
        target = 32'h0;
        for (int i = 0; i < WAYS; i++) begin
            if (btb_ram[query_idx][i].valid && btb_ram[query_idx][i].tag == query_tag) begin
                q_hit = 1'b1;
                q_way = i[1:0];
                target = {btb_ram[query_idx][i].target, 2'b00};
            end
        end
        hit = q_hit;
    end

    logic [19:0] upd_tag;
    logic        upd_hit;
    logic [1:0]  upd_hit_way;
    logic [1:0]  upd_replace_way;

    always_comb begin
        upd_tag = update_pc[31:12];
        upd_hit = 1'b0;
        upd_hit_way = 2'd0;
        for (int i = 0; i < WAYS; i++) begin
            if (btb_ram[update_idx][i].valid && btb_ram[update_idx][i].tag == upd_tag) begin
                upd_hit = 1'b1;
                upd_hit_way = i[1:0];
            end
        end
        upd_replace_way = plru_bits[update_idx][0] ? 2'd1 : 2'd0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRIES/WAYS; i++) begin
                plru_bits[i] <= '0;
                for (int j = 0; j < WAYS; j++)
                    btb_ram[i][j] <= '{tag: 20'h0, target: 30'h0, valid: 1'b0};
            end
        end else if (update_valid) begin
            if (upd_hit) begin
                btb_ram[update_idx][upd_hit_way].target <= update_target[31:2];
            end else begin
                btb_ram[update_idx][upd_replace_way].tag    <= upd_tag;
                btb_ram[update_idx][upd_replace_way].target <= update_target[31:2];
                btb_ram[update_idx][upd_replace_way].valid  <= 1'b1;
                plru_bits[update_idx] <= ~plru_bits[update_idx];
            end
        end
    end

endmodule
