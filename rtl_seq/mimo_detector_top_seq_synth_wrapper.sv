`include "fixed_point_pkg.sv"

// Synthesis-facing wrapper for the optimized sequential architecture.
// Vivado top-level synthesis is more robust with flat vector ports than with
// unpacked array ports, so this wrapper only repacks ports and preserves the
// verified rtl_seq/mimo_detector_top_seq behavior.
//
// Index mapping:
//   H index    = r*NT + c
//   y index    = r
//   xout index = i
//   bits index = i
module mimo_detector_top_seq_synth_wrapper #(
    parameter int NR = fixed_point_pkg::NR,
    parameter int NT = fixed_point_pkg::NT
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  logic [1:0] snr_level,
    input  logic signed [fixed_point_pkg::GBW_W-1:0] noise_var,

    input  logic [NR*NT*fixed_point_pkg::H_W-1:0] H_re_flat,
    input  logic [NR*NT*fixed_point_pkg::H_W-1:0] H_im_flat,
    input  logic [NR*fixed_point_pkg::Y_W-1:0]     y_re_flat,
    input  logic [NR*fixed_point_pkg::Y_W-1:0]     y_im_flat,

    output logic done,
    output logic busy,
    output logic [1:0] mode,
    output logic [4:0] num_iters,

    output logic [NT*fixed_point_pkg::XOUT_W-1:0] xout_re_flat,
    output logic [NT*fixed_point_pkg::XOUT_W-1:0] xout_im_flat,
    output logic [NT*2-1:0]                       bits_flat
);

    import fixed_point_pkg::*;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];
    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];
    logic [1:0] bits [NT];
    gs_mode_t mode_internal;

    always_comb begin
        for (int r = 0; r < NR; r++) begin
            y_re[r] = y_re_flat[r*Y_W +: Y_W];
            y_im[r] = y_im_flat[r*Y_W +: Y_W];

            for (int c = 0; c < NT; c++) begin
                H_re[r][c] = H_re_flat[((r*NT + c)*H_W) +: H_W];
                H_im[r][c] = H_im_flat[((r*NT + c)*H_W) +: H_W];
            end
        end

        for (int i = 0; i < NT; i++) begin
            xout_re_flat[i*XOUT_W +: XOUT_W] = xout_re[i];
            xout_im_flat[i*XOUT_W +: XOUT_W] = xout_im[i];
            bits_flat[i*2 +: 2] = bits[i];
        end

        mode = mode_internal;
    end

    mimo_detector_top_seq #(
        .NR(NR),
        .NT(NT)
    ) u_mimo_detector_top_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .snr_level(snr_level),
        .noise_var(noise_var),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .done(done),
        .busy(busy),
        .mode(mode_internal),
        .num_iters(num_iters),
        .bits(bits),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

endmodule
