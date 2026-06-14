// perceptron_predictor.sv
module perceptron_predictor (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] pc_query,
    output logic        pred_dir,
    output logic [ 7:0] pred_conf,

    input  logic        update_valid,
    input  logic [31:0] update_pc,
    input  logic        update_taken
);

    localparam NUM_PERCEPTRONS = 64;
    localparam DIM            = 8;
    localparam GHR_WIDTH      = 32;

    logic signed [7:0] weights [0:NUM_PERCEPTRONS-1][0:DIM-1];
    logic [GHR_WIDTH-1:0] ghr;

    logic [5:0] query_idx;
    assign query_idx = pc_query[7:2] ^ ghr[7:0];

    logic signed [15:0] dot_product;

    always_comb begin
        dot_product = 16'sd0;
        for (int i = 0; i < DIM; i++) begin
            if (ghr[i])
                dot_product = dot_product + {{8{weights[query_idx][i][7]}}, weights[query_idx][i]};
            else
                dot_product = dot_product - {{8{weights[query_idx][i][7]}}, weights[query_idx][i]};
        end
        pred_dir   = (dot_product >= 0);
        pred_conf  = (dot_product >= 0) ? dot_product[7:0] : (~dot_product[7:0] + 8'd1);
    end

    logic [5:0] update_idx;
    assign update_idx = update_pc[7:2] ^ ghr[7:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr <= '0;
            for (int i = 0; i < NUM_PERCEPTRONS; i++)
                for (int j = 0; j < DIM; j++)
                    weights[i][j] <= 8'sd0;
        end else begin
            if (update_valid) begin
                for (int i = 0; i < DIM; i++) begin
                    if ((update_taken && ghr[i]) || (!update_taken && !ghr[i])) begin
                        if (weights[update_idx][i] < 8'sd127)
                            weights[update_idx][i] <= weights[update_idx][i] + 8'sd1;
                    end else begin
                        if (weights[update_idx][i] > -8'sd128)
                            weights[update_idx][i] <= weights[update_idx][i] - 8'sd1;
                    end
                end
                ghr <= {ghr[GHR_WIDTH-2:0], update_taken};
            end
        end
    end

endmodule
