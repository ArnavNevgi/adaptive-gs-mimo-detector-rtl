`include "fixed_point_pkg.sv"

module qpsk_slicer_array #(
    parameter int N      = fixed_point_pkg::NT,
    parameter int XOUT_W = fixed_point_pkg::XOUT_W
) (
    input  logic signed [XOUT_W-1:0] xout_re [N],
    input  logic signed [XOUT_W-1:0] xout_im [N],

    output logic [1:0] bits [N]
);

    always_comb begin
        for (int i = 0; i < N; i++) begin
            // Same convention as qpsk_slicer:
            // bit[1] = imag sign
            // bit[0] = real sign
            bits[i][1] = xout_im[i][XOUT_W-1];
            bits[i][0] = xout_re[i][XOUT_W-1];
        end
    end

endmodule