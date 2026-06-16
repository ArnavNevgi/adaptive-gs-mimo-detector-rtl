`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_debug_vector2_seq_vs_ref;

    import fixed_point_pkg::*;
    import phase6_vectors_pkg::*;

    localparam int VEC = 2;

    logic clk;
    logic rst_n;

    logic gram_start;
    logic mf_start;
    logic regmet_start;
    logic gs_start;

    logic gram_done;
    logic gram_busy;
    logic mf_done;
    logic mf_busy;
    logic regmet_done;
    logic regmet_busy;
    logic gs_done_seq;
    logic gs_busy_seq;
    logic gs_done_ref;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];
    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];
    logic signed [GBW_W-1:0] noise_var;
    logic [4:0] num_iters;

    logic signed [GBW_W-1:0] G_ref_re [NT][NT];
    logic signed [GBW_W-1:0] G_ref_im [NT][NT];
    logic signed [GBW_W-1:0] G_seq_re [NT][NT];
    logic signed [GBW_W-1:0] G_seq_im [NT][NT];

    logic signed [GBW_W-1:0] b_ref_re [NT];
    logic signed [GBW_W-1:0] b_ref_im [NT];
    logic signed [GBW_W-1:0] b_seq_re [NT];
    logic signed [GBW_W-1:0] b_seq_im [NT];

    logic signed [GBW_W-1:0] W_ref_re [NT][NT];
    logic signed [GBW_W-1:0] W_ref_im [NT][NT];
    logic signed [GBW_W-1:0] W_seq_re [NT][NT];
    logic signed [GBW_W-1:0] W_seq_im [NT][NT];

    logic [31:0] diag_ref;
    logic [31:0] offdiag_ref;
    logic [31:0] diag_seq;
    logic [31:0] offdiag_seq;

    logic signed [X_W-1:0] x_ref_re [NT];
    logic signed [X_W-1:0] x_ref_im [NT];
    logic signed [X_W-1:0] x_seq_re [NT];
    logic signed [X_W-1:0] x_seq_im [NT];

    logic signed [XOUT_W-1:0] xout_ref_re [NT];
    logic signed [XOUT_W-1:0] xout_ref_im [NT];
    logic signed [XOUT_W-1:0] xout_seq_re [NT];
    logic signed [XOUT_W-1:0] xout_seq_im [NT];

    gram_matrix_compute u_gram_ref (
        .H_re(H_re),
        .H_im(H_im),
        .G_re(G_ref_re),
        .G_im(G_ref_im)
    );

    gram_matrix_seq u_gram_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(gram_start),
        .H_re(H_re),
        .H_im(H_im),
        .done(gram_done),
        .busy(gram_busy),
        .G_re(G_seq_re),
        .G_im(G_seq_im)
    );

    matched_filter_compute u_mf_ref (
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .b_re(b_ref_re),
        .b_im(b_ref_im)
    );

    matched_filter_seq u_mf_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(mf_start),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .done(mf_done),
        .busy(mf_busy),
        .b_re(b_seq_re),
        .b_im(b_seq_im)
    );

    regularization_unit u_reg_ref (
        .G_re(G_seq_re),
        .G_im(G_seq_im),
        .noise_var(noise_var),
        .W_re(W_ref_re),
        .W_im(W_ref_im)
    );

    condition_metric_unit u_metric_ref (
        .G_re(G_seq_re),
        .G_im(G_seq_im),
        .diag_sum(diag_ref),
        .offdiag_sum(offdiag_ref)
    );

    regularization_metric_seq u_regmet_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(regmet_start),
        .G_re(G_seq_re),
        .G_im(G_seq_im),
        .noise_var(noise_var),
        .done(regmet_done),
        .busy(regmet_busy),
        .W_re(W_seq_re),
        .W_im(W_seq_im),
        .diag_sum(diag_seq),
        .offdiag_sum(offdiag_seq)
    );

    gs_solver u_gs_ref (
        .clk(clk),
        .rst_n(rst_n),
        .start(gs_start),
        .num_iters(num_iters),
        .W_re(W_seq_re),
        .W_im(W_seq_im),
        .b_re(b_seq_re),
        .b_im(b_seq_im),
        .done(gs_done_ref),
        .x_re(x_ref_re),
        .x_im(x_ref_im)
    );

    gs_solver_seq u_gs_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(gs_start),
        .num_iters(num_iters),
        .W_re(W_seq_re),
        .W_im(W_seq_im),
        .b_re(b_seq_re),
        .b_im(b_seq_im),
        .done(gs_done_seq),
        .busy(gs_busy_seq),
        .x_re(x_seq_re),
        .x_im(x_seq_im)
    );

    x_to_xout_converter u_xout_ref (
        .x_re(x_ref_re),
        .x_im(x_ref_im),
        .xout_re(xout_ref_re),
        .xout_im(xout_ref_im)
    );

    x_to_xout_converter u_xout_seq (
        .x_re(x_seq_re),
        .x_im(x_seq_im),
        .xout_re(xout_seq_re),
        .xout_im(xout_seq_im)
    );

    always #5 clk = ~clk;

    task automatic clear_inputs;
        int r;
        int c;
        begin
            gram_start = 1'b0;
            mf_start = 1'b0;
            regmet_start = 1'b0;
            gs_start = 1'b0;
            noise_var = '0;
            num_iters = 5'd0;

            for (r = 0; r < NR; r++) begin
                y_re[r] = '0;
                y_im[r] = '0;
                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = '0;
                    H_im[r][c] = '0;
                end
            end
        end
    endtask

    task automatic load_vector2;
        int r;
        int c;
        begin
            noise_var = V_NOISE_VAR[VEC];
            num_iters = V_EXP_NUM_ITERS[VEC];

            for (r = 0; r < NR; r++) begin
                y_re[r] = V_Y_RE[VEC][r];
                y_im[r] = V_Y_IM[VEC][r];
                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = V_H_RE[VEC][r][c];
                    H_im[r][c] = V_H_IM[VEC][r][c];
                end
            end
        end
    endtask

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            clear_inputs();
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic pulse_gram;
        begin
            @(posedge clk);
            gram_start = 1'b1;
            @(posedge clk);
            gram_start = 1'b0;
        end
    endtask

    task automatic pulse_mf;
        begin
            @(posedge clk);
            mf_start = 1'b1;
            @(posedge clk);
            mf_start = 1'b0;
        end
    endtask

    task automatic pulse_regmet;
        begin
            @(posedge clk);
            regmet_start = 1'b1;
            @(posedge clk);
            regmet_start = 1'b0;
        end
    endtask

    task automatic pulse_gs;
        begin
            @(posedge clk);
            gs_start = 1'b1;
            @(posedge clk);
            gs_start = 1'b0;
        end
    endtask

    task automatic wait_gram_done;
        int timeout;
        begin
            timeout = 0;
            while (!gram_done && timeout < 1000) begin
                @(posedge clk);
                timeout++;
            end

            if (!gram_done) begin
                $display("TIMEOUT gram_matrix_seq");
                $fatal;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic wait_mf_done;
        int timeout;
        begin
            timeout = 0;
            while (!mf_done && timeout < 1000) begin
                @(posedge clk);
                timeout++;
            end

            if (!mf_done) begin
                $display("TIMEOUT matched_filter_seq");
                $fatal;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic wait_regmet_done;
        int timeout;
        begin
            timeout = 0;
            while (!regmet_done && timeout < 1000) begin
                @(posedge clk);
                timeout++;
            end

            if (!regmet_done) begin
                $display("TIMEOUT regularization_metric_seq");
                $fatal;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic wait_gs_done;
        int timeout;
        bit seen_ref;
        bit seen_seq;
        begin
            timeout = 0;
            seen_ref = 1'b0;
            seen_seq = 1'b0;

            while (!(seen_ref && seen_seq) && timeout < 10000) begin
                @(posedge clk);
                if (gs_done_ref) seen_ref = 1'b1;
                if (gs_done_seq) seen_seq = 1'b1;
                timeout++;
            end

            if (!(seen_ref && seen_seq)) begin
                $display("TIMEOUT gs_solver compare: seen_ref=%0d seen_seq=%0d",
                         seen_ref, seen_seq);
                $fatal;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic check_gram;
        int i;
        int j;
        begin
            for (i = 0; i < NT; i++) begin
                for (j = 0; j < NT; j++) begin
                    if (G_seq_re[i][j] !== G_ref_re[i][j]) begin
                        $display("FIRST MISMATCH G_re[%0d][%0d]: seq=%0d ref=%0d",
                                 i, j, G_seq_re[i][j], G_ref_re[i][j]);
                        $fatal;
                    end
                    if (G_seq_im[i][j] !== G_ref_im[i][j]) begin
                        $display("FIRST MISMATCH G_im[%0d][%0d]: seq=%0d ref=%0d",
                                 i, j, G_seq_im[i][j], G_ref_im[i][j]);
                        $fatal;
                    end
                end
            end
            $display("G_re/G_im exact match");
        end
    endtask

    task automatic check_matched_filter;
        int i;
        begin
            for (i = 0; i < NT; i++) begin
                if (b_seq_re[i] !== b_ref_re[i]) begin
                    $display("FIRST MISMATCH b_re[%0d]: seq=%0d ref=%0d",
                             i, b_seq_re[i], b_ref_re[i]);
                    $fatal;
                end
                if (b_seq_im[i] !== b_ref_im[i]) begin
                    $display("FIRST MISMATCH b_im[%0d]: seq=%0d ref=%0d",
                             i, b_seq_im[i], b_ref_im[i]);
                    $fatal;
                end
            end
            $display("b_re/b_im exact match");
        end
    endtask

    task automatic check_regmet;
        int i;
        int j;
        begin
            for (i = 0; i < NT; i++) begin
                for (j = 0; j < NT; j++) begin
                    if (W_seq_re[i][j] !== W_ref_re[i][j]) begin
                        $display("FIRST MISMATCH W_re[%0d][%0d]: seq=%0d ref=%0d",
                                 i, j, W_seq_re[i][j], W_ref_re[i][j]);
                        $fatal;
                    end
                    if (W_seq_im[i][j] !== W_ref_im[i][j]) begin
                        $display("FIRST MISMATCH W_im[%0d][%0d]: seq=%0d ref=%0d",
                                 i, j, W_seq_im[i][j], W_ref_im[i][j]);
                        $fatal;
                    end
                end
            end

            if (diag_seq !== diag_ref) begin
                $display("FIRST MISMATCH diag_sum: seq=%0d ref=%0d",
                         diag_seq, diag_ref);
                $fatal;
            end
            if (offdiag_seq !== offdiag_ref) begin
                $display("FIRST MISMATCH offdiag_sum: seq=%0d ref=%0d",
                         offdiag_seq, offdiag_ref);
                $fatal;
            end

            $display("W_re/W_im and diag_sum/offdiag_sum exact match");
        end
    endtask

    task automatic check_gs;
        int i;
        begin
            for (i = 0; i < NT; i++) begin
                if (x_seq_re[i] !== x_ref_re[i]) begin
                    $display("FIRST MISMATCH x_re[%0d]: seq=%0d ref=%0d",
                             i, x_seq_re[i], x_ref_re[i]);
                    $fatal;
                end
                if (x_seq_im[i] !== x_ref_im[i]) begin
                    $display("FIRST MISMATCH x_im[%0d]: seq=%0d ref=%0d",
                             i, x_seq_im[i], x_ref_im[i]);
                    $fatal;
                end
            end

            for (i = 0; i < NT; i++) begin
                if (xout_seq_re[i] !== xout_ref_re[i]) begin
                    $display("FIRST MISMATCH xout_re[%0d]: seq=%0d ref=%0d expected_pkg=%0d",
                             i, xout_seq_re[i], xout_ref_re[i], V_EXP_XOUT_RE[VEC][i]);
                    $fatal;
                end
                if (xout_seq_im[i] !== xout_ref_im[i]) begin
                    $display("FIRST MISMATCH xout_im[%0d]: seq=%0d ref=%0d expected_pkg=%0d",
                             i, xout_seq_im[i], xout_ref_im[i], V_EXP_XOUT_IM[VEC][i]);
                    $fatal;
                end
            end

            $display("x_re/x_im and xout_re/xout_im exact match");
        end
    endtask

    initial begin
        $display("Starting tb_debug_vector2_seq_vs_ref");

        clk = 1'b0;
        rst_n = 1'b0;

        apply_reset();
        load_vector2();
        #1;

        $display("Loaded Phase 6 vector %0d: snr_level=%0d noise_var=%0d num_iters=%0d",
                 VEC, V_SNR_LEVEL[VEC], noise_var, num_iters);

        pulse_gram();
        wait_gram_done();
        check_gram();

        pulse_mf();
        wait_mf_done();
        check_matched_filter();

        pulse_regmet();
        wait_regmet_done();
        check_regmet();

        pulse_gs();
        wait_gs_done();
        check_gs();

        $display("tb_debug_vector2_seq_vs_ref PASSED exact");
        $finish;
    end

endmodule
