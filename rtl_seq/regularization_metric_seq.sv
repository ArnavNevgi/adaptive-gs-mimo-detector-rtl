`include "fixed_point_pkg.sv"

module regularization_metric_seq #(
    parameter int NT = fixed_point_pkg::NT
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  var logic signed [fixed_point_pkg::GBW_W-1:0] G_re [NT][NT],
    input  var logic signed [fixed_point_pkg::GBW_W-1:0] G_im [NT][NT],
    input  logic signed [fixed_point_pkg::GBW_W-1:0] noise_var,

    output logic done,
    output logic busy,

    output logic signed [fixed_point_pkg::GBW_W-1:0] W_re [NT][NT],
    output logic signed [fixed_point_pkg::GBW_W-1:0] W_im [NT][NT],

    output logic [31:0] diag_sum,
    output logic [31:0] offdiag_sum
);

    import fixed_point_pkg::*;

    typedef enum logic [1:0] {
        S_IDLE,
        S_PROCESS
    } state_t;

    state_t state, state_n;

    logic [$clog2(NT)-1:0] i_idx;
    logic [$clog2(NT)-1:0] j_idx;

    logic [$clog2(NT)-1:0] i_idx_n;
    logic [$clog2(NT)-1:0] j_idx_n;

    logic [31:0] diag_acc;
    logic [31:0] offdiag_acc;

    logic [31:0] diag_acc_n;
    logic [31:0] offdiag_acc_n;

    logic done_n;
    logic busy_n;

    logic signed [GBW_W-1:0] w_re_current;
    logic signed [GBW_W-1:0] w_im_current;

    logic [GBW_W:0] abs_re;
    logic [GBW_W:0] abs_im;
    logic [GBW_W+1:0] mag_sum;
    logic [31:0] mag_sum_32;

    function automatic logic [GBW_W:0] abs_gbw(
        input logic signed [GBW_W-1:0] value
    );
        logic signed [GBW_W:0] ext_value;
        begin
            ext_value = {value[GBW_W-1], value};

            if (ext_value < 0) begin
                abs_gbw = -ext_value;
            end else begin
                abs_gbw = ext_value;
            end
        end
    endfunction

    always_comb begin
        if (i_idx == j_idx) begin
            w_re_current = G_re[i_idx][j_idx] + noise_var;
        end else begin
            w_re_current = G_re[i_idx][j_idx];
        end

        w_im_current = G_im[i_idx][j_idx];

        abs_re     = abs_gbw(G_re[i_idx][j_idx]);
        abs_im     = abs_gbw(G_im[i_idx][j_idx]);
        mag_sum    = abs_re + abs_im;
        mag_sum_32 = {{(32-(GBW_W+2)){1'b0}}, mag_sum};
    end

    always_comb begin
        state_n = state;

        i_idx_n = i_idx;
        j_idx_n = j_idx;

        diag_acc_n    = diag_acc;
        offdiag_acc_n = offdiag_acc;

        done_n = 1'b0;
        busy_n = busy;

        case (state)
            S_IDLE: begin
                done_n = 1'b0;
                busy_n = 1'b0;

                if (start) begin
                    busy_n        = 1'b1;
                    i_idx_n       = '0;
                    j_idx_n       = '0;
                    diag_acc_n    = 32'd0;
                    offdiag_acc_n = 32'd0;
                    state_n       = S_PROCESS;
                end
            end

            S_PROCESS: begin
                if (i_idx == j_idx) begin
                diag_acc_n = diag_acc + mag_sum_32;
            end else begin
                offdiag_acc_n = offdiag_acc + mag_sum_32;
            end

                if ((i_idx == NT-1) && (j_idx == NT-1)) begin
                    i_idx_n = '0;
                    j_idx_n = '0;
                    busy_n  = 1'b0;
                    done_n  = 1'b1;
                    state_n = S_IDLE;
                end else if (j_idx == NT-1) begin
                    j_idx_n = '0;
                    i_idx_n = i_idx + 1'b1;
                end else begin
                    j_idx_n = j_idx + 1'b1;
                end
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    integer rr;
    integer cc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;

            i_idx <= '0;
            j_idx <= '0;

            diag_acc    <= 32'd0;
            offdiag_acc <= 32'd0;

            diag_sum    <= 32'd0;
            offdiag_sum <= 32'd0;

            done <= 1'b0;
            busy <= 1'b0;

            for (rr = 0; rr < NT; rr++) begin
                for (cc = 0; cc < NT; cc++) begin
                    W_re[rr][cc] <= '0;
                    W_im[rr][cc] <= '0;
                end
            end
        end else begin
            state <= state_n;

            i_idx <= i_idx_n;
            j_idx <= j_idx_n;

            diag_acc    <= diag_acc_n;
            offdiag_acc <= offdiag_acc_n;

            done <= done_n;
            busy <= busy_n;

            if (state == S_PROCESS) begin
                W_re[i_idx][j_idx] <= w_re_current;
                W_im[i_idx][j_idx] <= w_im_current;
            end

            if ((state == S_PROCESS) && ((i_idx == NT-1) && (j_idx == NT-1))) begin
                diag_sum    <= diag_acc_n;
                offdiag_sum <= offdiag_acc_n;
            end
        end
    end

endmodule
