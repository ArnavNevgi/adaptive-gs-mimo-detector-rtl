`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_mimo_detector_top_seq_basic;

    import fixed_point_pkg::*;

    logic clk;
    logic rst_n;
    logic start;
    logic done;
    logic busy;

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

    int errors;

    mimo_detector_top_seq dut (
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
        .busy(busy),
        .mode(mode),
        .num_iters(num_iters),
        .bits(bits),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

    always #5 clk = ~clk;

    task automatic clear_inputs;
        int r;
        int c;
        begin
            for (r = 0; r < NR; r++) begin
                y_re[r] = '0;
                y_im[r] = '0;

                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = '0;
                    H_im[r][c] = '0;
                end
            end

            noise_var = '0;
            snr_level = 2'd0;
        end
    endtask

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            start = 1'b0;
            clear_inputs();

            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic setup_identity_qpsk_case;
        int i;
        begin
            clear_inputs();

            // H = I in Q4.12
            for (i = 0; i < NT; i++) begin
                H_re[i][i] = 16'sd4096;
                H_im[i][i] = 16'sd0;
            end

            // noise = 0, high SNR.
            // diag_sum > 0 and offdiag_sum = 0, so adaptive policy should select GS-4.
            noise_var = 20'sd0;
            snr_level = 2'd2;

            // QPSK symbols in Q4.12:
            // x0 = +1 + j
            // x1 = -1 + j
            // x2 = -1 - j
            // x3 = +1 - j
            //
            // With H = I and noise = 0, y = x.

            y_re[0] = 16'sd4096;   y_im[0] = 16'sd4096;
            y_re[1] = -16'sd4096;  y_im[1] = 16'sd4096;
            y_re[2] = -16'sd4096;  y_im[2] = -16'sd4096;
            y_re[3] = 16'sd4096;   y_im[3] = -16'sd4096;
        end
    endtask

    task automatic pulse_start;
        begin
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    task automatic wait_done;
        int timeout;
        begin
            timeout = 0;

            while (!done && timeout < 5000) begin
                @(posedge clk);
                timeout++;
            end

            if (!done) begin
                $error("Timeout waiting for done");
                errors++;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic check_identity_qpsk_case;
        begin
            if (mode !== MODE_GS4) begin
                $error("mode mismatch: got %0d expected MODE_GS4", mode);
                errors++;
            end

            if (num_iters !== 5'd4) begin
                $error("num_iters mismatch: got %0d expected 4", num_iters);
                errors++;
            end

            if (xout_re[0] !== 16'sd4096 || xout_im[0] !== 16'sd4096) begin
                $error("xout[0] mismatch: got (%0d,%0d)", xout_re[0], xout_im[0]);
                errors++;
            end

            if (xout_re[1] !== -16'sd4096 || xout_im[1] !== 16'sd4096) begin
                $error("xout[1] mismatch: got (%0d,%0d)", xout_re[1], xout_im[1]);
                errors++;
            end

            if (xout_re[2] !== -16'sd4096 || xout_im[2] !== -16'sd4096) begin
                $error("xout[2] mismatch: got (%0d,%0d)", xout_re[2], xout_im[2]);
                errors++;
            end

            if (xout_re[3] !== 16'sd4096 || xout_im[3] !== -16'sd4096) begin
                $error("xout[3] mismatch: got (%0d,%0d)", xout_re[3], xout_im[3]);
                errors++;
            end

            // bits[1] = imag sign, bits[0] = real sign.
            // +re +im -> 00
            // -re +im -> 01
            // -re -im -> 11
            // +re -im -> 10

            if (bits[0] !== 2'b00) begin
                $error("bits[0] mismatch: got %b expected 00", bits[0]);
                errors++;
            end

            if (bits[1] !== 2'b01) begin
                $error("bits[1] mismatch: got %b expected 01", bits[1]);
                errors++;
            end

            if (bits[2] !== 2'b11) begin
                $error("bits[2] mismatch: got %b expected 11", bits[2]);
                errors++;
            end

            if (bits[3] !== 2'b10) begin
                $error("bits[3] mismatch: got %b expected 10", bits[3]);
                errors++;
            end

            if (errors == 0) begin
                $display("PASS identity QPSK sequential top test");
            end
        end
    endtask

    initial begin
        $display("Starting tb_mimo_detector_top_seq_basic");

        clk    = 1'b0;
        rst_n  = 1'b0;
        start  = 1'b0;
        errors = 0;

        apply_reset();

        setup_identity_qpsk_case();
        pulse_start();
        wait_done();
        check_identity_qpsk_case();

        if (errors == 0) begin
            $display("tb_mimo_detector_top_seq_basic PASSED");
        end else begin
            $error("tb_mimo_detector_top_seq_basic FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule