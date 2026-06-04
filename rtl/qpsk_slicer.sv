`include "fixed_point_pkg.sv"

module qpsk_slicer #(
    parameter int W = fixed_point_pkg::XOUT_W
) (
    input  logic signed [W-1:0] x_re,
    input  logic signed [W-1:0] x_im,

    output logic bit0,
    output logic bit1
);

    always_comb begin
        bit0 = x_im[W-1];  // imag < 0
        bit1 = x_re[W-1];  // real < 0
    end

endmodule