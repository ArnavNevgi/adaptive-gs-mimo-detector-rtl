`include "fixed_point_pkg.sv"

module mimo_detector_top_seq #(
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
    input  var logic signed [fixed_point_pkg::H_W-1:0] H_re [NR][NT],
    input  var logic signed [fixed_point_pkg::H_W-1:0] H_im [NR][NT],

    // y in Q4.12
    input  var logic signed [fixed_point_pkg::Y_W-1:0] y_re [NR],
    input  var logic signed [fixed_point_pkg::Y_W-1:0] y_im [NR],

    output logic done,
    output logic busy,

    output fixed_point_pkg::gs_mode_t mode,
    output logic [4:0] num_iters,

    output logic [1:0] bits [NT],

    // Debug outputs
    output logic signed [fixed_point_pkg::XOUT_W-1:0] xout_re [NT],
    output logic signed [fixed_point_pkg::XOUT_W-1:0] xout_im [NT]
);

    import fixed_point_pkg::*;

    typedef enum logic [3:0] {
        S_IDLE,
        S_START_G,
        S_WAIT_G,
        S_START_B,
        S_WAIT_B,
        S_START_REGMET,
        S_WAIT_REGMET,
        S_START_GS,
        S_WAIT_GS,
        S_DONE
    } state_t;

    state_t state;

    logic gram_start;
    logic gram_done;
    logic gram_busy;

    logic mf_start;
    logic mf_done;
    logic mf_busy;

    logic regmet_start;
    logic regmet_done;
    logic regmet_busy;

    logic gs_start;
    logic gs_done;
    logic gs_busy;

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
    // Sequential G = H^H H
    // ------------------------------------------------------------

    gram_matrix_seq #(
        .NR(NR),
        .NT(NT)
    ) u_gram_matrix_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(gram_start),
        .H_re(H_re),
        .H_im(H_im),
        .done(gram_done),
        .busy(gram_busy),
        .G_re(G_re),
        .G_im(G_im)
    );

    // ------------------------------------------------------------
    // Sequential b = H^H y
    // ------------------------------------------------------------

    matched_filter_seq #(
        .NR(NR),
        .NT(NT)
    ) u_matched_filter_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(mf_start),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .done(mf_done),
        .busy(mf_busy),
        .b_re(b_re),
        .b_im(b_im)
    );

    // ------------------------------------------------------------
    // Sequential W = G + noise_var I and condition metric
    // ------------------------------------------------------------

    regularization_metric_seq #(
        .NT(NT)
    ) u_regularization_metric_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(regmet_start),
        .G_re(G_re),
        .G_im(G_im),
        .noise_var(noise_var),
        .done(regmet_done),
        .busy(regmet_busy),
        .W_re(W_re),
        .W_im(W_im),
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
    // Sequential GS solver
    // ------------------------------------------------------------

    gs_solver_seq #(
        .N(NT)
    ) u_gs_solver_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(gs_start),
        .num_iters(num_iters),
        .W_re(W_re),
        .W_im(W_im),
        .b_re(b_re),
        .b_im(b_im),
        .done(gs_done),
        .busy(gs_busy),
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

    // ------------------------------------------------------------
    // Top-level sequencing FSM
    // ------------------------------------------------------------

    always_comb begin
        gram_start   = 1'b0;
        mf_start     = 1'b0;
        regmet_start = 1'b0;
        gs_start     = 1'b0;

        case (state)
            S_START_G: begin
                gram_start = 1'b1;
            end

            S_START_B: begin
                mf_start = 1'b1;
            end

            S_START_REGMET: begin
                regmet_start = 1'b1;
            end

            S_START_GS: begin
                gs_start = 1'b1;
            end

            default: begin
                gram_start   = 1'b0;
                mf_start     = 1'b0;
                regmet_start = 1'b0;
                gs_start     = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
            busy  <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_START_G;
                    end
                end

                S_START_G: begin
                    state <= S_WAIT_G;
                end

                S_WAIT_G: begin
                    if (gram_done) begin
                        state <= S_START_B;
                    end
                end

                S_START_B: begin
                    state <= S_WAIT_B;
                end

                S_WAIT_B: begin
                    if (mf_done) begin
                        state <= S_START_REGMET;
                    end
                end

                S_START_REGMET: begin
                    state <= S_WAIT_REGMET;
                end

                S_WAIT_REGMET: begin
                    if (regmet_done) begin
                        state <= S_START_GS;
                    end
                end

                S_START_GS: begin
                    state <= S_WAIT_GS;
                end

                S_WAIT_GS: begin
                    if (gs_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule