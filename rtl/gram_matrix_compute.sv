`include "fixed_point_pkg.sv"

module gram_matrix_compute #(
    parameter int NR      = fixed_point_pkg::NR,
    parameter int NT      = fixed_point_pkg::NT,
    parameter int H_W     = fixed_point_pkg::H_W,
    parameter int H_FRAC  = fixed_point_pkg::H_FRAC,
    parameter int ACC_W   = fixed_point_pkg::ACC_W,
    parameter int ACC_FRAC = fixed_point_pkg::ACC_FRAC,
    parameter int OUT_W   = fixed_point_pkg::GBW_W,
    parameter int OUT_FRAC = fixed_point_pkg::GBW_FRAC
) (
    input  logic signed [H_W-1:0] H_re [NR][NT],
    input  logic signed [H_W-1:0] H_im [NR][NT],

    output logic signed [OUT_W-1:0] G_re [NT][NT],
    output logic signed [OUT_W-1:0] G_im [NT][NT]
);

    localparam int SHIFT = ACC_FRAC - OUT_FRAC;

    function automatic logic signed [OUT_W-1:0] acc_to_out(
        input logic signed [ACC_W-1:0] value
    );
        begin
            if (SHIFT >= 0)
                acc_to_out = value >>> SHIFT;
            else
                acc_to_out = value <<< (-SHIFT);
        end
    endfunction

    logic signed [ACC_W-1:0] prod_re;
    logic signed [ACC_W-1:0] prod_im;

    always_comb begin
        for (int i = 0; i < NT; i++) begin
            for (int j = 0; j < NT; j++) begin
                logic signed [ACC_W-1:0] acc_re;
                logic signed [ACC_W-1:0] acc_im;

                acc_re = '0;
                acc_im = '0;

                for (int r = 0; r < NR; r++) begin
                    // conj(H[r][i]) = H_re[r][i] - j H_im[r][i]
                    // Multiply conj(H[r][i]) * H[r][j]

                    logic signed [H_W-1:0] a_re;
                    logic signed [H_W-1:0] a_im;
                    logic signed [H_W-1:0] b_re;
                    logic signed [H_W-1:0] b_im;

                    logic signed [(2*H_W)-1:0] ac;
                    logic signed [(2*H_W)-1:0] bd;
                    logic signed [(2*H_W)-1:0] ad;
                    logic signed [(2*H_W)-1:0] bc;

                    logic signed [(2*H_W):0] re_full;
                    logic signed [(2*H_W):0] im_full;

                    a_re = H_re[r][i];
                    a_im = -H_im[r][i];
                    b_re = H_re[r][j];
                    b_im = H_im[r][j];

                    ac = a_re * b_re;
                    bd = a_im * b_im;
                    ad = a_re * b_im;
                    bc = a_im * b_re;

                    re_full = ac - bd;
                    im_full = ad + bc;

                    prod_re = re_full >>> ((2*H_FRAC) - ACC_FRAC);
                    prod_im = im_full >>> ((2*H_FRAC) - ACC_FRAC);

                    acc_re = acc_re + prod_re;
                    acc_im = acc_im + prod_im;
                end

                G_re[i][j] = acc_to_out(acc_re);
                G_im[i][j] = acc_to_out(acc_im);
            end
        end
    end

endmodule