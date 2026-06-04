`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_matched_filter_compute;

    import fixed_point_pkg::*;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];

    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    logic signed [GBW_W-1:0] b_re [NT];
    logic signed [GBW_W-1:0] b_im [NT];

    matched_filter_compute dut (
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .b_re(b_re),
        .b_im(b_im)
    );

    task clear_inputs;
        begin
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

    initial begin
        $display("Starting tb_matched_filter_compute");

        clear_inputs();

        // H = identity
        for (int i = 0; i < NT; i++) begin
            H_re[i][i] = 16'sd4096;
        end

        // y vector
        y_re[0] = 16'sd4096;   y_im[0] = 16'sd0;       // 1 + 0j
        y_re[1] = 16'sd2048;   y_im[1] = 16'sd2048;    // 0.5 + 0.5j
        y_re[2] = -16'sd4096;  y_im[2] = 16'sd0;       // -1 + 0j
        y_re[3] = 16'sd0;      y_im[3] = -16'sd4096;   // -j

        #1;

        if (b_re[0] !== 20'sd4096 || b_im[0] !== 20'sd0) begin
            $display("FAIL b0 = (%0d,%0d)", b_re[0], b_im[0]);
            $fatal;
        end

        if (b_re[1] !== 20'sd2048 || b_im[1] !== 20'sd2048) begin
            $display("FAIL b1 = (%0d,%0d)", b_re[1], b_im[1]);
            $fatal;
        end

        if (b_re[2] !== -20'sd4096 || b_im[2] !== 20'sd0) begin
            $display("FAIL b2 = (%0d,%0d)", b_re[2], b_im[2]);
            $fatal;
        end

        if (b_re[3] !== 20'sd0 || b_im[3] !== -20'sd4096) begin
            $display("FAIL b3 = (%0d,%0d)", b_re[3], b_im[3]);
            $fatal;
        end

        $display("PASS: matched filter identity test");
        $display("tb_matched_filter_compute PASSED");
        $finish;
    end

endmodule