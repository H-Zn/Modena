"""
分支目标缓冲模块

"""
module btb (
    //全局信号
    //时钟
    input logic clk,
    //复位，低有效
    input logic rst_n,
    // 查询接口
    input logic [31:0] pc_query,
    // 更新接口
    input logic update_valid,
    input logic [31:0] update_pc,
    input logic [31:0] update_target


    output logic hit,
    output logic [31:0] target,
);

    localparam ENTRIES = 512;
    localparam WAYS = 2;
    localparam INDEX_BITS = $clog2(ENTRIES / WAYS); // 8位

    typedef struct packed {
        logic [19:0] tag;
        logic [29:0] target;  // 30位，因最低两位总是0
        logic valid;
    } btb_entry;

    btb_entry btb [0:ENTRIES/WAYS-1][0:WAYS-1];
    logic [WAYS-1:0] plru_bits [0:ENTRIES/WAYS-1]; // 伪LRU

    logic [INDEX_BITS-1:0] query_idx;
    logic [INDEX_BITS-1:0] update_idx;
    assign query_idx = pc_query[INDEX_BITS+1:2];
    assign update_idx = update_pc[INDEX_BITS+1:2];

    // 查询
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

    // 更新
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ENTRIES/WAYS; i++) begin
                plru_bits[i] <= '0;
                for (int j = 0; j < WAYS; j++)
                    btb[i][j] <= '{tag: 20'h0, target: 30'h0, valid: 1'b0};
            end
        end else if (update_valid) begin
            logic [19:0] upd_tag;
            upd_tag = update_pc[31:12];
            // 查找是否命中
            bit upd_hit;
            int  hit_way;
            upd_hit = 1'b0;
            for (int i = 0; i < WAYS; i++) begin
                if (btb[update_idx][i].valid && btb[update_idx][i].tag == upd_tag) begin
                    upd_hit = 1'b1;
                    hit_way = i;
                end
            end
            if (upd_hit) begin
                // 命中：更新目标
                btb[update_idx][hit_way].target <= update_target[31:2];
            end else begin
                // 未命中：分配 (采用PLRU)
                int replace_way;
                // 简单的树PLRU：2路
                replace_way = plru_bits[update_idx][0];
                btb[update_idx][replace_way].tag <= upd_tag;
                
                btb[update_idx][replace_way].target <= update_target[31:2];
                btb[update_idx][replace_way].valid <= 1'b1;
                plru_bits[update_idx] <= ~plru_bits[update_idx];
            end
        end
    end

endmodule