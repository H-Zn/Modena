// perceptron_predictor.sv
module perceptron_predictor (
    input  logic        clk,
    input  logic        rst_n,

    // 查询接口
    input  logic [31:0] pc_query,
    output logic        pred_dir,
    output logic [ 7:0] pred_conf,

    // 更新接口
    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic        update_taken
);

    // 参数
    localparam NUM_PERCEPTRONS = 64;
    localparam DIM            = 8;
    localparam GHR_WIDTH      = 32;

    // 权重存储 (有符号8位)
    logic signed [7:0] weights [0:NUM_PERCEPTRONS-1][0:DIM-1];
    logic [GHR_WIDTH-1:0] ghr;

    // 索引计算函数
    function automatic logic [5:0] get_index(logic [31:0] pc);
        return pc[7:2] ^ ghr[7:0];
    endfunction

    // 查询逻辑
    logic [5:0] query_idx;
    logic signed [15:0] dot_product;
    assign query_idx = get_index(pc_query);

    always_comb begin
        dot_product = 16'sd0;
        for (int i = 0; i < DIM; i++) begin
            if (ghr[i])
                dot_product += weights[query_idx][i];
            else
                dot_product -= weights[query_idx][i];
        end
        pred_dir = (dot_product >= 0);
        conf = (dot_product >= 0) ? dot_product[7:0] : (~dot_product[7:0] + 1'b1);
    end

    // 更新逻辑
    logic [5:0] update_idx;
    assign update_idx = get_index(update_pc);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr <= '0;
            for (int i = 0; i < NUM_PERCEPTRONS; i++)
                for (int j = 0; j < DIM; j++)
                    weights[i][j] <= 8'sd0;
        end else begin
            if (update_valid) begin
                // 权重更新 (感知器学习规则)
                for (int i = 0; i < DIM; i++) begin
                    if ((update_taken && ghr[i]) || (!update_taken && !ghr[i])) begin
                        if (weights[update_idx][i] < 8'sd127)
                            weights[update_idx][i] <= weights[update_idx][i] + 1;
                    end else begin
                        if (weights[update_idx][i] > -8'sd128)
                            weights[update_idx][i] <= weights[update_idx][i] - 1;
                    end
                end
                // 更新全局历史
                ghr <= {ghr[GHR_WIDTH-2:0], update_taken};
            end
        end
    end

endmodule