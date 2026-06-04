`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_solver_slicer_chain;

    import fixed_point_pkg::*;

    logic clk;
    logic rst_n;
    logic start;
    logic done;

    logic [4:0] num_iters;

    logic signed [GBW_W-1:0] W_re [NT][NT];
    logic signed [GBW_W-1:0] W_im [NT][NT];

    logic signed [GBW_W-1:0] b_re [NT];
    logic signed [GBW_W-1:0] b_im [NT];

    logic signed [X_W-1:0] x_re [NT];
    logic signed [X_W-1:0] x_im [NT];

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

    logic [1:0] bits [NT];

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

    x_to_xout_converter u_x_to_xout (
        .x_re(x_re),
        .x_im(x_im),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

    qpsk_slicer_array u_slicer_array (
        .xout_re(xout_re),
        .xout_im(xout_im),
        .bits(bits)
    );

    always #5 clk = ~clk;

    task clear_inputs;
        begin
            for (int i = 0; i < NT; i++) begin
                b_re[i] = '0;
                b_im[i] = '0;

                for (int j = 0; j < NT; j++) begin
                    W_re[i][j] = '0;
                    W_im[i][j] = '0;
                end
            end
        end
    endtask

    task setup_nondiagonal_real_system;
        begin
            clear_inputs();

            // W in Q8.12
            //
            // W =
            // [2.0  0.5  0     0
            //  0.5  2.0  0     0
            //  0    0    2.0   0.25
            //  0    0    0.25  2.0]
            //
            // Known solution:
            // x = [1.0, 0.5, -1.0, 0.25]
            //
            // b = W*x =
            // [2.25, 1.5, -1.9375, 0.25]

            W_re[0][0] = 20'sd8192;   // 2.0
            W_re[0][1] = 20'sd2048;   // 0.5

            W_re[1][0] = 20'sd2048;   // 0.5
            W_re[1][1] = 20'sd8192;   // 2.0

            W_re[2][2] = 20'sd8192;   // 2.0
            W_re[2][3] = 20'sd1024;   // 0.25

            W_re[3][2] = 20'sd1024;   // 0.25
            W_re[3][3] = 20'sd8192;   // 2.0

            b_re[0] = 20'sd9216;    b_im[0] = 20'sd0;   // 2.25
            b_re[1] = 20'sd6144;    b_im[1] = 20'sd0;   // 1.5
            b_re[2] = -20'sd7936;   b_im[2] = 20'sd0;   // -1.9375
            b_re[3] = 20'sd1024;    b_im[3] = 20'sd0;   // 0.25
        end
    endtask

    task check_bits(
        input int idx,
        input logic [1:0] expected
    );
        begin
            if (bits[idx] !== expected) begin
                $display("FAIL bits[%0d]: got %b expected %b",
                         idx, bits[idx], expected);
                $display("x[%0d]     = (%0d,%0d)", idx, x_re[idx], x_im[idx]);
                $display("xout[%0d]  = (%0d,%0d)", idx, xout_re[idx], xout_im[idx]);
                $fatal;
            end
            else begin
                $display("PASS bits[%0d] = %b, xout=(%0d,%0d)",
                         idx, bits[idx], xout_re[idx], xout_im[idx]);
            end
        end
    endtask

    task check_xout_close(
        input int idx,
        input logic signed [XOUT_W-1:0] exp_re,
        input logic signed [XOUT_W-1:0] exp_im,
        input int tolerance
    );
        int diff_re;
        int diff_im;
        begin
            diff_re = xout_re[idx] - exp_re;
            diff_im = xout_im[idx] - exp_im;

            if (diff_re < 0) diff_re = -diff_re;
            if (diff_im < 0) diff_im = -diff_im;

            if (diff_re > tolerance || diff_im > tolerance) begin
                $display("FAIL xout[%0d]: got (%0d,%0d), expected (%0d,%0d), diff=(%0d,%0d), tol=%0d",
                         idx, xout_re[idx], xout_im[idx], exp_re, exp_im, diff_re, diff_im, tolerance);
                $fatal;
            end
            else begin
                $display("PASS xout[%0d]: got (%0d,%0d), expected (%0d,%0d), diff=(%0d,%0d)",
                         idx, xout_re[idx], xout_im[idx], exp_re, exp_im, diff_re, diff_im);
            end
        end
    endtask

    initial begin
        $display("Starting tb_solver_slicer_chain");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        num_iters = 5'd16;

        clear_inputs();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        setup_nondiagonal_real_system();

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        for (int timeout = 0; timeout < 500; timeout++) begin
            if (done) break;
            @(posedge clk);
        end

        if (!done) begin
            $display("FAIL: timeout waiting for gs_solver done");
            $fatal;
        end

        #1;

        // Expected x in Q4.12 after converter:
        // x = [1.0, 0.5, -1.0, 0.25]
        //
        // 1.0  -> 4096
        // 0.5  -> 2048
        // -1.0 -> -4096
        // 0.25 -> 1024

        check_xout_close(0, 16'sd4096,  16'sd0, 100);
        check_xout_close(1, 16'sd2048,  16'sd0, 100);
        check_xout_close(2, -16'sd4096, 16'sd0, 100);
        check_xout_close(3, 16'sd1024,  16'sd0, 100);

        // QPSK slicer convention:
        // bit[1] = imag sign
        // bit[0] = real sign
        //
        // x0 = +real +0imag -> 00
        // x1 = +real +0imag -> 00
        // x2 = -real +0imag -> 01
        // x3 = +real +0imag -> 00

        check_bits(0, 2'b00);
        check_bits(1, 2'b00);
        check_bits(2, 2'b01);
        check_bits(3, 2'b00);

        $display("tb_solver_slicer_chain PASSED");
        $finish;
    end

endmodule