`include "fixed_point_pkg.sv"

module complex_mult #(
    parameter int A_W     = fixed_point_pkg::H_W,
    parameter int A_FRAC  = fixed_point_pkg::H_FRAC,
    parameter int B_W     = fixed_point_pkg::H_W,
    parameter int B_FRAC  = fixed_point_pkg::H_FRAC,
    parameter int OUT_W   = fixed_point_pkg::ACC_W,
    parameter int OUT_FRAC = fixed_point_pkg::ACC_FRAC
) (
    input  logic signed [A_W-1:0] a_re,
    input  logic signed [A_W-1:0] a_im,
    input  logic signed [B_W-1:0] b_re,
    input  logic signed [B_W-1:0] b_im,

    output logic signed [OUT_W-1:0] y_re,
    output logic signed [OUT_W-1:0] y_im
);

    localparam int PROD_W = A_W + B_W;
    localparam int PROD_FRAC = A_FRAC + B_FRAC;
    localparam int SHIFT = PROD_FRAC - OUT_FRAC;

    logic signed [PROD_W-1:0] ac;
    logic signed [PROD_W-1:0] bd;
    logic signed [PROD_W-1:0] ad;
    logic signed [PROD_W-1:0] bc;

    logic signed [PROD_W:0] re_full;
    logic signed [PROD_W:0] im_full;

    always_comb begin
        ac = a_re * b_re;
        bd = a_im * b_im;
        ad = a_re * b_im;
        bc = a_im * b_re;

        re_full = ac - bd;
        im_full = ad + bc;

        if (SHIFT >= 0) begin
            y_re = re_full >>> SHIFT;
            y_im = im_full >>> SHIFT;
        end else begin
            y_re = re_full <<< (-SHIFT);
            y_im = im_full <<< (-SHIFT);
        end
    end

endmodule