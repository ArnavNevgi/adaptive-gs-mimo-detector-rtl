`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_gs_solver;

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

    gs_solver dut (
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

    task setup_identity_system;
        begin
            clear_inputs();

            // W = I in Q8.12
            for (int i = 0; i < NT; i++) begin
                W_re[i][i] = 20'sd4096;
                W_im[i][i] = 20'sd0;
            end

            // b in Q8.12
            b_re[0] = 20'sd4096;   b_im[0] = 20'sd0;       // 1 + 0j
            b_re[1] = 20'sd2048;   b_im[1] = 20'sd2048;    // 0.5 + 0.5j
            b_re[2] = -20'sd4096;  b_im[2] = 20'sd0;       // -1 + 0j
            b_re[3] = 20'sd0;      b_im[3] = -20'sd4096;   // -j
        end
    endtask

    task run_solver(input logic [4:0] iters);
        integer timeout;
        begin
            setup_identity_system();
            num_iters = iters;

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            timeout = 0;
            while (!done && timeout < 200) begin
                @(posedge clk);
                timeout++;
            end

            if (!done) begin
                $display("FAIL: timeout waiting for done, iters=%0d", iters);
                $fatal;
            end

            // Output x is Q6.16.
            // Expected:
            // 1.0   -> 65536
            // 0.5   -> 32768
            // -1.0  -> -65536

            if (x_re[0] !== 22'sd65536 || x_im[0] !== 22'sd0) begin
                $display("FAIL x0: got (%0d,%0d)", x_re[0], x_im[0]);
                $fatal;
            end

            if (x_re[1] !== 22'sd32768 || x_im[1] !== 22'sd32768) begin
                $display("FAIL x1: got (%0d,%0d)", x_re[1], x_im[1]);
                $fatal;
            end

            if (x_re[2] !== -22'sd65536 || x_im[2] !== 22'sd0) begin
                $display("FAIL x2: got (%0d,%0d)", x_re[2], x_im[2]);
                $fatal;
            end

            if (x_re[3] !== 22'sd0 || x_im[3] !== -22'sd65536) begin
                $display("FAIL x3: got (%0d,%0d)", x_re[3], x_im[3]);
                $fatal;
            end

            $display("PASS GS solver identity system, iters=%0d", iters);
        end
    endtask

        task check_close_x(
        input int idx,
        input logic signed [X_W-1:0] exp_re,
        input logic signed [X_W-1:0] exp_im,
        input int tolerance
    );
        int diff_re;
        int diff_im;
        begin
            diff_re = x_re[idx] - exp_re;
            diff_im = x_im[idx] - exp_im;

            if (diff_re < 0) diff_re = -diff_re;
            if (diff_im < 0) diff_im = -diff_im;

            if (diff_re > tolerance || diff_im > tolerance) begin
                $display("FAIL x[%0d]: got (%0d,%0d), expected (%0d,%0d), diff=(%0d,%0d), tol=%0d",
                        idx, x_re[idx], x_im[idx], exp_re, exp_im, diff_re, diff_im, tolerance);
                $fatal;
            end
            else begin
                $display("PASS x[%0d]: got (%0d,%0d), expected (%0d,%0d), diff=(%0d,%0d)",
                        idx, x_re[idx], x_im[idx], exp_re, exp_im, diff_re, diff_im);
            end
        end
    endtask

        task setup_nondiagonal_real_system;
        begin
            clear_inputs();

            // W in Q8.12
            // W =
            // [2.0  0.5  0    0
            //  0.5  2.0  0    0
            //  0    0    2.0  0.25
            //  0    0    0.25 2.0]

            W_re[0][0] = 20'sd8192;   // 2.0
            W_re[0][1] = 20'sd2048;   // 0.5

            W_re[1][0] = 20'sd2048;   // 0.5
            W_re[1][1] = 20'sd8192;   // 2.0

            W_re[2][2] = 20'sd8192;   // 2.0
            W_re[2][3] = 20'sd1024;   // 0.25

            W_re[3][2] = 20'sd1024;   // 0.25
            W_re[3][3] = 20'sd8192;   // 2.0

            // b = W*x for x = [1, 0.5, -1, 0.25]
            // b0 = 2.25
            // b1 = 1.5
            // b2 = -1.9375
            // b3 = 0.25

            b_re[0] = 20'sd9216;    b_im[0] = 20'sd0;     // 2.25
            b_re[1] = 20'sd6144;    b_im[1] = 20'sd0;     // 1.5
            b_re[2] = -20'sd7936;   b_im[2] = 20'sd0;     // -1.9375
            b_re[3] = 20'sd1024;    b_im[3] = 20'sd0;     // 0.25
        end
    endtask

    task run_solver_nondiagonal(input logic [4:0] iters);
    integer timeout;
    begin
        setup_nondiagonal_real_system();
        num_iters = iters;

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        timeout = 0;
        while (!done && timeout < 500) begin
            @(posedge clk);
            timeout++;
        end

        if (!done) begin
            $display("FAIL: timeout waiting for done in non-diagonal test, iters=%0d", iters);
            $fatal;
        end

        // Expected x in Q6.16:
        // [1.0, 0.5, -1.0, 0.25]
        //
        // Because GS is iterative and fixed-point quantized,
        // allow tolerance. GS-16 should be very close.
        check_close_x(0, 22'sd65536,  22'sd0, 1500);
        check_close_x(1, 22'sd32768,  22'sd0, 1500);
        check_close_x(2, -22'sd65536, 22'sd0, 1500);
        check_close_x(3, 22'sd16384,  22'sd0, 1500);

        $display("PASS GS solver non-diagonal real system, iters=%0d", iters);
    end
endtask

    initial begin
        $display("Starting tb_gs_solver");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        num_iters = 5'd4;
        clear_inputs();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        run_solver(5'd4);
        run_solver(5'd8);
        run_solver(5'd16);
        run_solver_nondiagonal(5'd16);

        $display("tb_gs_solver PASSED");
        $finish;
    end

endmodule