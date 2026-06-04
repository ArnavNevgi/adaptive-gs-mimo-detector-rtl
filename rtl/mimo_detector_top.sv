`include "fixed_point_pkg.sv"

module mimo_detector_top #(
    parameter int NR = fixed_point_pkg::NR,
    parameter int NT = fixed_point_pkg::NT
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    // snr_level:
    // 0 = low SNR
    // 1 = medium SNR, snr >= 4 dB
    // 2 = high SNR, snr >= 8 dB
    input  logic [1:0] snr_level,

    // Q8.12 noise variance
    input  logic signed [fixed_point_pkg::GBW_W-1:0] noise_var,

    // H in Q4.12
    input  logic signed [fixed_point_pkg::H_W-1:0] H_re [NR][NT],
    input  logic signed [fixed_point_pkg::H_W-1:0] H_im [NR][NT],

    // y in Q4.12
    input  logic signed [fixed_point_pkg::Y_W-1:0] y_re [NR],
    input  logic signed [fixed_point_pkg::Y_W-1:0] y_im [NR],

    output logic done,

    output fixed_point_pkg::gs_mode_t mode,
    output logic [4:0] num_iters,

    output logic [1:0] bits [NT],

    // Debug outputs
    output logic signed [fixed_point_pkg::XOUT_W-1:0] xout_re [NT],
    output logic signed [fixed_point_pkg::XOUT_W-1:0] xout_im [NT]
);

    import fixed_point_pkg::*;

    // ------------------------------------------------------------
    // Internal signals
    // ------------------------------------------------------------

    logic signed [GBW_W-1:0] G_re [NT][NT];
    logic signed [GBW_W-1:0] G_im [NT][NT];

    logic signed [GBW_W-1:0] W_re [NT][NT];
    logic signed [GBW_W-1:0] W_im [NT][NT];

    logic signed [GBW_W-1:0] b_re [NT];
    logic signed [GBW_W-1:0] b_im [NT];

    logic [31:0] diag_sum;
    logic [31:0] offdiag_sum;

    logic signed [X_W-1:0] x_re [NT];
    logic signed [X_W-1:0] x_im [NT];

    // ------------------------------------------------------------
    // G = H^H H
    // ------------------------------------------------------------

    gram_matrix_compute u_gram_matrix_compute (
        .H_re(H_re),
        .H_im(H_im),
        .G_re(G_re),
        .G_im(G_im)
    );

    // ------------------------------------------------------------
    // b = H^H y
    // ------------------------------------------------------------

    matched_filter_compute u_matched_filter_compute (
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .b_re(b_re),
        .b_im(b_im)
    );

    // ------------------------------------------------------------
    // W = G + noise_var * I
    // ------------------------------------------------------------

    regularization_unit u_regularization_unit (
        .G_re(G_re),
        .G_im(G_im),
        .noise_var(noise_var),
        .W_re(W_re),
        .W_im(W_im)
    );

    // ------------------------------------------------------------
    // Condition metric from G
    // ------------------------------------------------------------

    condition_metric_unit u_condition_metric_unit (
        .G_re(G_re),
        .G_im(G_im),
        .diag_sum(diag_sum),
        .offdiag_sum(offdiag_sum)
    );

    // ------------------------------------------------------------
    // Adaptive mode selection
    // ------------------------------------------------------------

    mode_select_unit u_mode_select_unit (
        .snr_level(snr_level),
        .diag_sum(diag_sum),
        .offdiag_sum(offdiag_sum),
        .mode(mode),
        .num_iters(num_iters)
    );

    // ------------------------------------------------------------
    // GS solver
    // ------------------------------------------------------------

    gs_solver u_gs_solver (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .num_iters(num_iters),
        .W_re(W_re),
        .W_im(W_im),
        .b_re(b_re),
        .b_im(b_im),
        .done(done),
        .x_re(x_re),
        .x_im(x_im)
    );

    // ------------------------------------------------------------
    // Q6.16 -> Q4.12
    // ------------------------------------------------------------

    x_to_xout_converter u_x_to_xout_converter (
        .x_re(x_re),
        .x_im(x_im),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

    // ------------------------------------------------------------
    // QPSK slicer array
    // ------------------------------------------------------------

    qpsk_slicer_array u_qpsk_slicer_array (
        .xout_re(xout_re),
        .xout_im(xout_im),
        .bits(bits)
    );

endmodule