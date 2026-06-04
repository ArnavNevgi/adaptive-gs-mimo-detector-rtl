`include "fixed_point_pkg.sv"

module regularization_unit #(
    parameter int N      = fixed_point_pkg::NT,
    parameter int W      = fixed_point_pkg::GBW_W
) (
    input  logic signed [W-1:0] G_re [N][N],
    input  logic signed [W-1:0] G_im [N][N],
    input  logic signed [W-1:0] noise_var,

    output logic signed [W-1:0] W_re [N][N],
    output logic signed [W-1:0] W_im [N][N]
);

    always_comb begin
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                W_re[i][j] = G_re[i][j];
                W_im[i][j] = G_im[i][j];

                if (i == j) begin
                    W_re[i][j] = G_re[i][j] + noise_var;
                end
            end
        end
    end

endmodule
