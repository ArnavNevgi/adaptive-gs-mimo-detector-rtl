`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_mimo_detector_top_vectors;

    import fixed_point_pkg::*;
    import phase6_vectors_pkg::*;

    localparam int XOUT_TOL = 4;

    logic clk;
    logic rst_n;
    logic start;
    logic done;

    logic [1:0] snr_level;
    logic signed [GBW_W-1:0] noise_var;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];

    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    gs_mode_t mode;
    logic [4:0] num_iters;
    logic [1:0] actual_mode;

    logic [1:0] bits [NT];

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

    assign actual_mode = mode;

    mimo_detector_top dut (
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
        .mode(mode),
        .num_iters(num_iters),
        .bits(bits),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

    always #5 clk = ~clk;

    function automatic int abs_int(input int value);
        begin
            if (value < 0)
                abs_int = -value;
            else
                abs_int = value;
        end
    endfunction

    task apply_vector(input int v);
        begin
            snr_level = V_SNR_LEVEL[v];
            noise_var = V_NOISE_VAR[v];

            for (int r = 0; r < NR; r++) begin
                y_re[r] = V_Y_RE[v][r];
                y_im[r] = V_Y_IM[v][r];
                for (int c = 0; c < NT; c++) begin
                    H_re[r][c] = V_H_RE[v][r][c];
                    H_im[r][c] = V_H_IM[v][r][c];
                end
            end
        end
    endtask

    task check_mode_prestart(input int v);
        begin
            if (actual_mode !== V_EXP_MODE[v]) begin
                $display("FAIL vector %0d mode: got %0d expected %0d",
                         v, actual_mode, V_EXP_MODE[v]);
                $fatal;
            end

            if (num_iters !== V_EXP_NUM_ITERS[v]) begin
                $display("FAIL vector %0d num_iters: got %0d expected %0d",
                         v, num_iters, V_EXP_NUM_ITERS[v]);
                $fatal;
            end
        end
    endtask

    task wait_for_done(input int v);
        int timeout;
        begin
            timeout = 0;
            while (!done && timeout < 500) begin
                @(posedge clk);
                timeout++;
            end

            if (!done) begin
                $display("FAIL vector %0d: timeout waiting for done", v);
                $fatal;
            end
        end
    endtask

    task compare_outputs(input int v);
        int diff_re;
        int diff_im;
        begin
            for (int i = 0; i < NT; i++) begin
                if (bits[i] !== V_EXP_BITS[v][i]) begin
                    $display("FAIL vector %0d stream %0d bits: got %b expected %b",
                             v, i, bits[i], V_EXP_BITS[v][i]);
                    $display("  xout got=(%0d,%0d), expected=(%0d,%0d)",
                             xout_re[i], xout_im[i],
                             V_EXP_XOUT_RE[v][i], V_EXP_XOUT_IM[v][i]);
                    $fatal;
                end

                diff_re = abs_int(xout_re[i] - V_EXP_XOUT_RE[v][i]);
                diff_im = abs_int(xout_im[i] - V_EXP_XOUT_IM[v][i]);

                if (diff_re > XOUT_TOL || diff_im > XOUT_TOL) begin
                    $display("FAIL vector %0d stream %0d xout diff too large", v, i);
                    $display("  got=(%0d,%0d), expected=(%0d,%0d), diff=(%0d,%0d), tol=%0d",
                             xout_re[i], xout_im[i],
                             V_EXP_XOUT_RE[v][i], V_EXP_XOUT_IM[v][i],
                             diff_re, diff_im, XOUT_TOL);
                    $fatal;
                end
                else if (diff_re != 0 || diff_im != 0) begin
                    $display("WARN vector %0d stream %0d xout within tolerance: diff=(%0d,%0d)",
                             v, i, diff_re, diff_im);
                end
            end
        end
    endtask

    task run_vector(input int v);
        begin
            apply_vector(v);
            #1;
            check_mode_prestart(v);

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            wait_for_done(v);
            #1;
            compare_outputs(v);

            $display("PASS vector %0d: mode=%0d num_iters=%0d", v, actual_mode, num_iters);
            @(posedge clk);
        end
    endtask

    initial begin
        $display("Starting tb_mimo_detector_top_vectors");
        $display("NUM_PHASE6_VECTORS = %0d", NUM_PHASE6_VECTORS);

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        snr_level = 2'd0;
        noise_var = '0;

        for (int r = 0; r < NR; r++) begin
            y_re[r] = '0;
            y_im[r] = '0;
            for (int c = 0; c < NT; c++) begin
                H_re[r][c] = '0;
                H_im[r][c] = '0;
            end
        end

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        for (int v = 0; v < NUM_PHASE6_VECTORS; v++) begin
            run_vector(v);
        end

        $display("tb_mimo_detector_top_vectors PASSED");
        $finish;
    end

endmodule
