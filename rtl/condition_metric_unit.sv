`include "fixed_point_pkg.sv"

module condition_metric_unit #(
    parameter int N        = fixed_point_pkg::NT,
    parameter int IN_W     = fixed_point_pkg::GBW_W,
    parameter int METRIC_W = 32
) (
    input  var logic signed [IN_W-1:0] G_re [N][N],
    input  var logic signed [IN_W-1:0] G_im [N][N],

    output logic [METRIC_W-1:0] diag_sum,
    output logic [METRIC_W-1:0] offdiag_sum
);

    function automatic logic [IN_W-1:0] abs_signed(
        input logic signed [IN_W-1:0] value
    );
        begin
            if (value < 0)
                abs_signed = -value;
            else
                abs_signed = value;
        end
    endfunction

    logic [METRIC_W-1:0] mag_approx;

    always_comb begin
        diag_sum    = '0;
        offdiag_sum = '0;

        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                mag_approx = {{(METRIC_W-IN_W){1'b0}}, abs_signed(G_re[i][j])}
                           + {{(METRIC_W-IN_W){1'b0}}, abs_signed(G_im[i][j])};

                if (i == j)
                    diag_sum = diag_sum + mag_approx;
                else
                    offdiag_sum = offdiag_sum + mag_approx;
            end
        end
    end

endmodule
