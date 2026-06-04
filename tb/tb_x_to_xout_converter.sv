`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_x_to_xout_converter;

    import fixed_point_pkg::*;

    logic signed [X_W-1:0]    x_re    [NT];
    logic signed [X_W-1:0]    x_im    [NT];

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

    x_to_xout_converter dut (
        .x_re(x_re),
        .x_im(x_im),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

    task check_value(
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
                $display("PASS xout[%0d]: (%0d,%0d)", idx, xout_re[idx], xout_im[idx]);
            end
        end
    endtask

    initial begin
        $display("Starting tb_x_to_xout_converter");

        // Normal Q6.16 -> Q4.12 conversion
        x_re[0] = 22'sd65536;    x_im[0] = 22'sd0;        // 1 + 0j
        x_re[1] = 22'sd32768;    x_im[1] = 22'sd32768;    // 0.5 + 0.5j
        x_re[2] = -22'sd65536;   x_im[2] = 22'sd0;        // -1 + 0j
        x_re[3] = 22'sd0;        x_im[3] = -22'sd65536;   // -j

        #1;

        check_value(0, 16'sd4096,  16'sd0);
        check_value(1, 16'sd2048,  16'sd2048);
        check_value(2, -16'sd4096, 16'sd0);
        check_value(3, 16'sd0,     -16'sd4096);

        // Saturation test
        // Q4.12 signed 16-bit max = 32767, min = -32768.
        x_re[0] = 22'sd1048576;    // too large after >>4 = 65536
        x_im[0] = -22'sd1048576;   // too negative after >>4 = -65536

        #1;

        check_value(0, 16'sd32767, -16'sd32768);

        $display("tb_x_to_xout_converter PASSED");
        $finish;
    end

endmodule