`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_mimo_detector_top;

    import fixed_point_pkg::*;

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

    logic [1:0] bits [NT];

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

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

    task clear_inputs;
        begin
            noise_var = '0;
            snr_level = 2'd0;

            for (int r = 0; r < NR; r++) begin
                y_re[r] = '0;
                y_im[r] = '0;

                for (int c = 0; c < NT; c++) begin
                    H_re[r][c] = '0;
                    H_im[r][c] = '0;
                end
            end
        end
    endtask

    task setup_identity_qpsk_case;
        begin
            clear_inputs();

            // H = I in Q4.12
            for (int i = 0; i < NT; i++) begin
                H_re[i][i] = 16'sd4096;
                H_im[i][i] = 16'sd0;
            end

            // High SNR.
            // For H = I:
            // diag_sum = 4 * 4096 = 16384
            // offdiag_sum = 0
            // Therefore mode should select GS-4.
            snr_level = 2'd2;

            // noise = 0 for exact identity behavior
            noise_var = 20'sd0;

            // y in Q4.12
            // stream 0: +re +im -> 00
            y_re[0] = 16'sd4096;
            y_im[0] = 16'sd4096;

            // stream 1: -re +im -> 01
            y_re[1] = -16'sd4096;
            y_im[1] = 16'sd4096;

            // stream 2: -re -im -> 11
            y_re[2] = -16'sd4096;
            y_im[2] = -16'sd4096;

            // stream 3: +re -im -> 10
            y_re[3] = 16'sd4096;
            y_im[3] = -16'sd4096;
        end
    endtask

    task check_bits(
        input int idx,
        input logic [1:0] expected
    );
        begin
            if (bits[idx] !== expected) begin
                $display("FAIL bits[%0d]: got %b expected %b", idx, bits[idx], expected);
                $display("xout[%0d] = (%0d,%0d)", idx, xout_re[idx], xout_im[idx]);
                $fatal;
            end
            else begin
                $display("PASS bits[%0d] = %b, xout=(%0d,%0d)",
                         idx, bits[idx], xout_re[idx], xout_im[idx]);
            end
        end
    endtask

    task check_xout(
        input int idx,
        input logic signed [XOUT_W-1:0] exp_re,
        input logic signed [XOUT_W-1:0] exp_im
    );
        begin
            if (xout_re[idx] !== exp_re || xout_im[idx] !== exp_im) begin
                $display("FAIL xout[%0d]: got (%0d,%0d), expected (%0d,%0d)",
                         idx, xout_re[idx], xout_im[idx], exp_re, exp_im);
                $fatal;
            end
            else begin
                $display("PASS xout[%0d] = (%0d,%0d)", idx, xout_re[idx], xout_im[idx]);
            end
        end
    endtask

    initial begin
        $display("Starting tb_mimo_detector_top");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;

        clear_inputs();

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        setup_identity_qpsk_case();

        // Allow combinational front-end to settle before start pulse.
        #1;

        if (mode !== MODE_GS4 || num_iters !== 5'd4) begin
            $display("FAIL mode select: mode=%0d num_iters=%0d, expected MODE_GS4/4",
                     mode, num_iters);
            $fatal;
        end
        else begin
            $display("PASS mode select: mode=%0d num_iters=%0d", mode, num_iters);
        end

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        for (int timeout = 0; timeout < 300; timeout++) begin
            if (done) break;
            @(posedge clk);
        end

        if (!done) begin
            $display("FAIL: timeout waiting for detector done");
            $fatal;
        end

        #1;

        // Expected xout in Q4.12 should match y because H=I, noise=0.
        check_xout(0, 16'sd4096,  16'sd4096);
        check_xout(1, -16'sd4096, 16'sd4096);
        check_xout(2, -16'sd4096, -16'sd4096);
        check_xout(3, 16'sd4096,  -16'sd4096);

        check_bits(0, 2'b00);
        check_bits(1, 2'b01);
        check_bits(2, 2'b11);
        check_bits(3, 2'b10);

        $display("tb_mimo_detector_top PASSED");
        $finish;
    end

endmodule