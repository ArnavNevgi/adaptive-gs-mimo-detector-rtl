`include "fixed_point_pkg.sv"

module gs_solver_seq #(
    parameter int N        = fixed_point_pkg::NT,
    parameter int W_W      = fixed_point_pkg::GBW_W,
    parameter int W_FRAC   = fixed_point_pkg::GBW_FRAC,
    parameter int B_W      = fixed_point_pkg::GBW_W,
    parameter int B_FRAC   = fixed_point_pkg::GBW_FRAC,
    parameter int X_W      = fixed_point_pkg::X_W,
    parameter int X_FRAC   = fixed_point_pkg::X_FRAC,
    parameter int ACC_W    = fixed_point_pkg::ACC_W,
    parameter int ACC_FRAC = fixed_point_pkg::ACC_FRAC
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  logic [4:0] num_iters,

    input  var logic signed [W_W-1:0] W_re [N][N],
    input  var logic signed [W_W-1:0] W_im [N][N],

    input  var logic signed [B_W-1:0] b_re [N],
    input  var logic signed [B_W-1:0] b_im [N],

    output logic done,
    output logic busy,

    output logic signed [X_W-1:0] x_re [N],
    output logic signed [X_W-1:0] x_im [N]
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_CLEAR,
        S_INIT_DIV,
        S_ITER_START,
        S_UPDATE_INIT,
        S_UPDATE_ACCUM,
        S_UPDATE_WRITE,
        S_DONE
    } state_t;

    state_t state;

    logic [4:0] iter_count;

    logic [$clog2(N)-1:0] idx;
    logic [$clog2(N)-1:0] j_idx;

    logic signed [X_W-1:0] x_old_re [N];
    logic signed [X_W-1:0] x_old_im [N];

    logic signed [ACC_W-1:0] sum_re;
    logic signed [ACC_W-1:0] sum_im;

    logic signed [ACC_W-1:0] prod_re;
    logic signed [ACC_W-1:0] prod_im;

    logic signed [ACC_W-1:0] numerator_re;
    logic signed [ACC_W-1:0] numerator_im;

    logic signed [X_W-1:0] xj_re;
    logic signed [X_W-1:0] xj_im;

    // ------------------------------------------------------------
    // Fixed-point helper functions
    // Must match rtl/gs_solver.sv
    // ------------------------------------------------------------

    function automatic logic signed [X_W-1:0] div_q_to_x(
        input logic signed [ACC_W-1:0] num,
        input logic signed [W_W-1:0] den
    );
        localparam int DIV_SHIFT = X_FRAC + W_FRAC - ACC_FRAC;

        logic signed [ACC_W+X_FRAC+W_FRAC-1:0] num_shift;
        logic signed [ACC_W+X_FRAC+W_FRAC-1:0] quot;

        begin
            if (den == 0) begin
                div_q_to_x = '0;
            end else begin
                if (DIV_SHIFT >= 0)
                    num_shift = num <<< DIV_SHIFT;
                else
                    num_shift = num >>> (-DIV_SHIFT);

                quot = num_shift / den;
                div_q_to_x = quot[X_W-1:0];
            end
        end
    endfunction

    function automatic logic signed [ACC_W-1:0] mult_wx_to_acc(
        input logic signed [W_W-1:0] w,
        input logic signed [X_W-1:0] x
    );
        localparam int PROD_W    = W_W + X_W;
        localparam int PROD_FRAC = W_FRAC + X_FRAC;
        localparam int SHIFT     = PROD_FRAC - ACC_FRAC;

        logic signed [PROD_W-1:0] prod;

        begin
            prod = w * x;

            if (SHIFT >= 0)
                mult_wx_to_acc = prod >>> SHIFT;
            else
                mult_wx_to_acc = prod <<< (-SHIFT);
        end
    endfunction

    function automatic logic signed [ACC_W-1:0] b_to_acc(
        input logic signed [B_W-1:0] value
    );
        localparam int SHIFT = ACC_FRAC - B_FRAC;

        begin
            if (SHIFT >= 0)
                b_to_acc = value <<< SHIFT;
            else
                b_to_acc = value >>> (-SHIFT);
        end
    endfunction

    // ------------------------------------------------------------
    // Sequential MAC datapath for current idx, j_idx
    // ------------------------------------------------------------

    always_comb begin
        if (j_idx < idx) begin
            xj_re = x_re[j_idx];
            xj_im = x_im[j_idx];
        end else begin
            xj_re = x_old_re[j_idx];
            xj_im = x_old_im[j_idx];
        end

        // Complex multiply W[idx][j] * x[j]
        // (a+jb)(c+jd) = (ac-bd) + j(ad+bc)

        prod_re = mult_wx_to_acc(W_re[idx][j_idx], xj_re)
                - mult_wx_to_acc(W_im[idx][j_idx], xj_im);

        prod_im = mult_wx_to_acc(W_re[idx][j_idx], xj_im)
                + mult_wx_to_acc(W_im[idx][j_idx], xj_re);

        numerator_re = b_to_acc(b_re[idx]) - sum_re;
        numerator_im = b_to_acc(b_im[idx]) - sum_im;
    end

    integer ii;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            iter_count <= '0;
            idx        <= '0;
            j_idx      <= '0;

            sum_re <= '0;
            sum_im <= '0;

            done <= 1'b0;
            busy <= 1'b0;

            for (ii = 0; ii < N; ii++) begin
                x_re[ii]     <= '0;
                x_im[ii]     <= '0;
                x_old_re[ii] <= '0;
                x_old_im[ii] <= '0;
            end
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy       <= 1'b0;
                    iter_count <= '0;
                    idx        <= '0;
                    j_idx      <= '0;
                    sum_re     <= '0;
                    sum_im     <= '0;

                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    for (ii = 0; ii < N; ii++) begin
                        x_re[ii]     <= '0;
                        x_im[ii]     <= '0;
                        x_old_re[ii] <= '0;
                        x_old_im[ii] <= '0;
                    end

                    idx   <= '0;
                    state <= S_INIT_DIV;
                end

                S_INIT_DIV: begin
                    // Diagonal initialization:
                    // x0[i] = b[i] / W[i][i]
                    x_re[idx] <= div_q_to_x(b_to_acc(b_re[idx]), W_re[idx][idx]);
                    x_im[idx] <= div_q_to_x(b_to_acc(b_im[idx]), W_re[idx][idx]);

                    if (idx == N-1) begin
                        idx        <= '0;
                        iter_count <= '0;
                        state      <= S_ITER_START;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                S_ITER_START: begin
                    for (ii = 0; ii < N; ii++) begin
                        x_old_re[ii] <= x_re[ii];
                        x_old_im[ii] <= x_im[ii];
                    end

                    idx    <= '0;
                    j_idx  <= '0;
                    sum_re <= '0;
                    sum_im <= '0;
                    state  <= S_UPDATE_INIT;
                end

                S_UPDATE_INIT: begin
                    j_idx  <= '0;
                    sum_re <= '0;
                    sum_im <= '0;
                    state  <= S_UPDATE_ACCUM;
                end

                S_UPDATE_ACCUM: begin
                    if (j_idx != idx) begin
                        sum_re <= sum_re + prod_re;
                        sum_im <= sum_im + prod_im;
                    end

                    if (j_idx == N-1) begin
                        state <= S_UPDATE_WRITE;
                    end else begin
                        j_idx <= j_idx + 1'b1;
                    end
                end

                S_UPDATE_WRITE: begin
                    // Same assumption as original gs_solver:
                    // W diagonal is treated as real-dominant.
                    x_re[idx] <= div_q_to_x(numerator_re, W_re[idx][idx]);
                    x_im[idx] <= div_q_to_x(numerator_im, W_re[idx][idx]);

                    if (idx == N-1) begin
                        idx        <= '0;
                        iter_count <= iter_count + 1'b1;

                        if (iter_count + 1'b1 >= num_iters) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_ITER_START;
                        end
                    end else begin
                        idx   <= idx + 1'b1;
                        state <= S_UPDATE_INIT;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule