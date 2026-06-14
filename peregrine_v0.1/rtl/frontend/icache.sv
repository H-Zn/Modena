module icache (
    input  logic        clk,
    input  logic        rst_n,

    // 取指接口
    input  logic [31:0] req_pc,
    input  logic        req_valid,
    output logic        req_ready,
    output logic [31:0] rsp_data,
    output logic        rsp_valid,

    // AXI接口 (略，仅作示意)
    output logic        axi_arvalid,
    input  logic        axi_arready,
    output logic [31:0] axi_araddr,
    input  logic        axi_rvalid,
    input  logic [31:0] axi_rdata
);

    // 参数
    localparam CACHE_SIZE   = 16*1024;
    localparam LINE_SIZE    = 32;
    localparam WAYS         = 4;
    localparam NUM_SETS     = CACHE_SIZE / (LINE_SIZE * WAYS); // 128
    localparam INDEX_BITS   = $clog2(NUM_SETS);    // 7
    localparam OFFSET_BITS  = $clog2(LINE_SIZE);   // 5
    localparam TAG_BITS     = 32 - INDEX_BITS - OFFSET_BITS; // 20

    // Cache存储结构
    typedef struct packed {
        logic [TAG_BITS-1:0] tag;
        logic [LINE_SIZE*8-1:0] data;
        logic valid;
        logic dirty;  // I-Cache只读，可省略dirty
    } cache_line_t;

    cache_line_t cache [0:NUM_SETS-1][0:WAYS-1];
    logic [WAYS-2:0] plru_tree [0:NUM_SETS-1]; // 树PLRU，3位用于4路

    // 状态机
    typedef enum logic [1:0] {IDLE, MISS, FILL} state_t;
    state_t state, next_state;

    // 请求锁存
    logic [31:0] saved_pc;
    logic [INDEX_BITS-1:0] saved_idx;
    logic [TAG_BITS-1:0]  saved_tag;

    // 访问分解
    logic [INDEX_BITS-1:0] req_idx;
    logic [TAG_BITS-1:0]   req_tag;
    logic [OFFSET_BITS-1:0] req_off;
    assign {req_tag, req_idx, req_off} = req_pc[31:2];

    // 命中检测
    logic hit;
    int  hit_way;
    always_comb begin
        hit = 1'b0;
        hit_way = 0;
        for (int i = 0; i < WAYS; i++) begin
            if (cache[req_idx][i].valid && cache[req_idx][i].tag == req_tag) begin
                hit = 1'b1;
                hit_way = i;
            end
        end
    end

    // 数据输出
    always_comb begin
        if (hit) begin
            case (req_off[4:2])
                3'd0: rsp_data = cache[req_idx][hit_way].data[31:0];
                3'd1: rsp_data = cache[req_idx][hit_way].data[63:32];
                3'd2: rsp_data = cache[req_idx][hit_way].data[95:64];
                3'd3: rsp_data = cache[req_idx][hit_way].data[127:96];
                3'd4: rsp_data = cache[req_idx][hit_way].data[159:128];
                3'd5: rsp_data = cache[req_idx][hit_way].data[191:160];
                3'd6: rsp_data = cache[req_idx][hit_way].data[223:192];
                3'd7: rsp_data = cache[req_idx][hit_way].data[255:224];
            endcase
        end else
            rsp_data = '0;
    end

    // 状态机 (简化)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            for (int i = 0; i < NUM_SETS; i++) begin
                plru_tree[i] <= '0;
                for (int j = 0; j < WAYS; j++)
                    cache[i][j].valid <= 1'b0;
            end
        end else begin
            state <= next_state;
            // PLRU更新 (命中时)
            if (state == IDLE && req_valid && hit) begin
                // 更新PLRU (略去详细位操作)
                // ...
            end
            // 填充处理 (简略)
            // ...
        end
    end

    // 组合逻辑次态 (略去AXI交互细节)
    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (req_valid && !hit) next_state = MISS;
            MISS: if (axi_arready) next_state = FILL;
            FILL: if (axi_rvalid) next_state = IDLE;
        endcase
    end

    assign req_ready = (state == IDLE) && hit;
    assign rsp_valid = req_ready;

    // AXI读地址通道
    assign axi_arvalid = (state == MISS);
    assign axi_araddr  = {saved_tag, saved_idx, 5'b0};

endmodule