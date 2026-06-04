`include "fixed_point_pkg.sv"

module gs_solver #(
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

    input  logic signed [W_W-1:0] W_re [N][N],
    input  logic signed [W_W-1:0] W_im [N][N],

    input  logic signed [B_W-1:0] b_re [N],
    input  logic signed [B_W-1:0] b_im [N],

    output logic done,

    output logic signed [X_W-1:0] x_re [N],
    output logic signed [X_W-1:0] x_im [N]
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_INIT,
        S_ITER_START,
        S_UPDATE,
        S_DONE
    } state_t;

    state_t state, state_n;

    logic [4:0] iter_count;
    logic [$clog2(N)-1:0] idx;

    logic signed [X_W-1:0] x_old_re [N];
    logic signed [X_W-1:0] x_old_im [N];

    // ------------------------------------------------------------
    // Fixed-point helper functions
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
            end
            else begin
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
        localparam int PROD_W = W_W + X_W;
        localparam int PROD_FRAC = W_FRAC + X_FRAC;
        localparam int SHIFT = PROD_FRAC - ACC_FRAC;

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
    // GS update combinational calculation for current idx
    // ------------------------------------------------------------

    logic signed [ACC_W-1:0] sum_re;
    logic signed [ACC_W-1:0] sum_im;

    logic signed [ACC_W-1:0] prod_re;
    logic signed [ACC_W-1:0] prod_im;

    logic signed [ACC_W-1:0] numerator_re;
    logic signed [ACC_W-1:0] numerator_im;

    always_comb begin
        sum_re = '0;
        sum_im = '0;

        for (int j = 0; j < N; j++) begin
            if (j != idx) begin
                logic signed [X_W-1:0] xj_re;
                logic signed [X_W-1:0] xj_im;

                if (j < idx) begin
                    xj_re = x_re[j];
                    xj_im = x_im[j];
                end
                else begin
                    xj_re = x_old_re[j];
                    xj_im = x_old_im[j];
                end

                // Complex multiply W[idx][j] * x[j]
                // (a+jb)(c+jd) = (ac-bd) + j(ad+bc)

                prod_re = mult_wx_to_acc(W_re[idx][j], xj_re)
                        - mult_wx_to_acc(W_im[idx][j], xj_im);

                prod_im = mult_wx_to_acc(W_re[idx][j], xj_im)
                        + mult_wx_to_acc(W_im[idx][j], xj_re);

                sum_re = sum_re + prod_re;
                sum_im = sum_im + prod_im;
            end
        end

        numerator_re = b_to_acc(b_re[idx]) - sum_re;
        numerator_im = b_to_acc(b_im[idx]) - sum_im;
    end

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            iter_count <= '0;
            idx <= '0;
            done <= 1'b0;

            for (int i = 0; i < N; i++) begin
                x_re[i] <= '0;
                x_im[i] <= '0;
                x_old_re[i] <= '0;
                x_old_im[i] <= '0;
            end
        end
        else begin
            state <= state_n;
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    iter_count <= '0;
                    idx <= '0;
                    if (start) begin
                        for (int i = 0; i < N; i++) begin
                            x_re[i] <= '0;
                            x_im[i] <= '0;
                            x_old_re[i] <= '0;
                            x_old_im[i] <= '0;
                        end
                    end
                end

                S_INIT: begin
                    // Diagonal initialization:
                    // x0[i] = b[i] / W[i][i]
                    for (int i = 0; i < N; i++) begin
                        x_re[i] <= div_q_to_x(b_to_acc(b_re[i]), W_re[i][i]);
                        x_im[i] <= div_q_to_x(b_to_acc(b_im[i]), W_re[i][i]);
                    end
                    iter_count <= '0;
                    idx <= '0;
                end

                S_ITER_START: begin
                    for (int i = 0; i < N; i++) begin
                        x_old_re[i] <= x_re[i];
                        x_old_im[i] <= x_im[i];
                    end
                    idx <= '0;
                end

                S_UPDATE: begin
                    // Assumption for first pass:
                    // W diagonal is real-dominant. Divide real and imag numerator by W_re[ii].
                    // Later: replace with complex reciprocal if needed.
                    x_re[idx] <= div_q_to_x(numerator_re, W_re[idx][idx]);
                    x_im[idx] <= div_q_to_x(numerator_im, W_re[idx][idx]);

                    if (idx == N-1) begin
                        idx <= '0;
                        iter_count <= iter_count + 1'b1;
                    end
                    else begin
                        idx <= idx + 1'b1;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (start)
                    state_n = S_INIT;
            end

            S_INIT: begin
                state_n = S_ITER_START;
            end

            S_ITER_START: begin
                state_n = S_UPDATE;
            end

            S_UPDATE: begin
                if ((idx == N-1) && (iter_count + 1'b1 >= num_iters))
                    state_n = S_DONE;
                else if (idx == N-1)
                    state_n = S_ITER_START;
                else
                    state_n = S_UPDATE;
            end

            S_DONE: begin
                state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

endmodule