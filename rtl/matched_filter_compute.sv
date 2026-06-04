`include "fixed_point_pkg.sv"

module matched_filter_compute #(
    parameter int NR      = fixed_point_pkg::NR,
    parameter int NT      = fixed_point_pkg::NT,
    parameter int H_W     = fixed_point_pkg::H_W,
    parameter int H_FRAC  = fixed_point_pkg::H_FRAC,
    parameter int Y_W     = fixed_point_pkg::Y_W,
    parameter int Y_FRAC  = fixed_point_pkg::Y_FRAC,
    parameter int ACC_W   = fixed_point_pkg::ACC_W,
    parameter int ACC_FRAC = fixed_point_pkg::ACC_FRAC,
    parameter int OUT_W   = fixed_point_pkg::GBW_W,
    parameter int OUT_FRAC = fixed_point_pkg::GBW_FRAC
) (
    input  logic signed [H_W-1:0] H_re [NR][NT],
    input  logic signed [H_W-1:0] H_im [NR][NT],

    input  logic signed [Y_W-1:0] y_re [NR],
    input  logic signed [Y_W-1:0] y_im [NR],

    output logic signed [OUT_W-1:0] b_re [NT],
    output logic signed [OUT_W-1:0] b_im [NT]
);

    localparam int PROD_FRAC = H_FRAC + Y_FRAC;
    localparam int SHIFT_TO_ACC = PROD_FRAC - ACC_FRAC;
    localparam int SHIFT_TO_OUT = ACC_FRAC - OUT_FRAC;

    function automatic logic signed [OUT_W-1:0] acc_to_out(
        input logic signed [ACC_W-1:0] value
    );
        begin
            if (SHIFT_TO_OUT >= 0)
                acc_to_out = value >>> SHIFT_TO_OUT;
            else
                acc_to_out = value <<< (-SHIFT_TO_OUT);
        end
    endfunction

    always_comb begin
        for (int i = 0; i < NT; i++) begin
            logic signed [ACC_W-1:0] acc_re;
            logic signed [ACC_W-1:0] acc_im;

            acc_re = '0;
            acc_im = '0;

            for (int r = 0; r < NR; r++) begin
                logic signed [H_W-1:0] a_re;
                logic signed [H_W-1:0] a_im;
                logic signed [Y_W-1:0] c_re;
                logic signed [Y_W-1:0] c_im;

                logic signed [(H_W+Y_W)-1:0] ac;
                logic signed [(H_W+Y_W)-1:0] bd;
                logic signed [(H_W+Y_W)-1:0] ad;
                logic signed [(H_W+Y_W)-1:0] bc;

                logic signed [(H_W+Y_W):0] re_full;
                logic signed [(H_W+Y_W):0] im_full;

                logic signed [ACC_W-1:0] prod_re;
                logic signed [ACC_W-1:0] prod_im;

                // conj(H[r][i])
                a_re = H_re[r][i];
                a_im = -H_im[r][i];

                c_re = y_re[r];
                c_im = y_im[r];

                ac = a_re * c_re;
                bd = a_im * c_im;
                ad = a_re * c_im;
                bc = a_im * c_re;

                re_full = ac - bd;
                im_full = ad + bc;

                prod_re = re_full >>> SHIFT_TO_ACC;
                prod_im = im_full >>> SHIFT_TO_ACC;

                acc_re = acc_re + prod_re;
                acc_im = acc_im + prod_im;
            end

            b_re[i] = acc_to_out(acc_re);
            b_im[i] = acc_to_out(acc_im);
        end
    end

endmodule