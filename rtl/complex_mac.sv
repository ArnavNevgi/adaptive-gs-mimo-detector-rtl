`include "fixed_point_pkg.sv"

module complex_mac #(
    parameter int A_W      = fixed_point_pkg::H_W,
    parameter int A_FRAC   = fixed_point_pkg::H_FRAC,
    parameter int B_W      = fixed_point_pkg::H_W,
    parameter int B_FRAC   = fixed_point_pkg::H_FRAC,
    parameter int ACC_W    = fixed_point_pkg::ACC_W,
    parameter int ACC_FRAC = fixed_point_pkg::ACC_FRAC
) (
    input  logic signed [A_W-1:0]   a_re,
    input  logic signed [A_W-1:0]   a_im,
    input  logic signed [B_W-1:0]   b_re,
    input  logic signed [B_W-1:0]   b_im,

    input  logic signed [ACC_W-1:0] acc_in_re,
    input  logic signed [ACC_W-1:0] acc_in_im,

    output logic signed [ACC_W-1:0] acc_out_re,
    output logic signed [ACC_W-1:0] acc_out_im
);

    logic signed [ACC_W-1:0] mult_re;
    logic signed [ACC_W-1:0] mult_im;

    complex_mult #(
        .A_W(A_W),
        .A_FRAC(A_FRAC),
        .B_W(B_W),
        .B_FRAC(B_FRAC),
        .OUT_W(ACC_W),
        .OUT_FRAC(ACC_FRAC)
    ) u_mult (
        .a_re(a_re),
        .a_im(a_im),
        .b_re(b_re),
        .b_im(b_im),
        .y_re(mult_re),
        .y_im(mult_im)
    );

    always_comb begin
        acc_out_re = acc_in_re + mult_re;
        acc_out_im = acc_in_im + mult_im;
    end

endmodule