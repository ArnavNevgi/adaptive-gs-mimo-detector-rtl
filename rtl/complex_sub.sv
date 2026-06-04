`include "fixed_point_pkg.sv"

module complex_sub #(
    parameter int W = fixed_point_pkg::GBW_W
) (
    input  logic signed [W-1:0] a_re,
    input  logic signed [W-1:0] a_im,
    input  logic signed [W-1:0] b_re,
    input  logic signed [W-1:0] b_im,
    output logic signed [W-1:0] y_re,
    output logic signed [W-1:0] y_im
);

    always_comb begin
        y_re = a_re - b_re;
        y_im = a_im - b_im;
    end

endmodule