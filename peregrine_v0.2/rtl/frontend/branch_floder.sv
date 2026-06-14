module branch_folder (
    input  logic        is_branch,
    input  logic        pred_dir,
    input  logic [ 7:0] conf,
    input  logic        btb_hit,
    input  logic [31:0] btb_target,

    output logic        fold_en,
    output logic [31:0] fold_target
);

    // 折叠阈值 (可配置)
    localparam THRESHOLD = 8'd64;

    assign fold_en = is_branch && pred_dir && btb_hit && (conf >= THRESHOLD);
    assign fold_target = btb_target;

endmodule