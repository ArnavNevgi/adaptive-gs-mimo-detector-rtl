`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_complex_mult;

    import fixed_point_pkg::*;

    logic signed [H_W-1:0] a_re;
    logic signed [H_W-1:0] a_im;
    logic signed [H_W-1:0] b_re;
    logic signed [H_W-1:0] b_im;

    logic signed [ACC_W-1:0] y_re;
    logic signed [ACC_W-1:0] y_im;

    complex_mult #(
        .A_W(H_W),
        .A_FRAC(H_FRAC),
        .B_W(H_W),
        .B_FRAC(H_FRAC),
        .OUT_W(ACC_W),
        .OUT_FRAC(ACC_FRAC)
    ) dut (
        .a_re(a_re),
        .a_im(a_im),
        .b_re(b_re),
        .b_im(b_im),
        .y_re(y_re),
        .y_im(y_im)
    );

    task check_mult(
        input logic signed [H_W-1:0] t_a_re,
        input logic signed [H_W-1:0] t_a_im,
        input logic signed [H_W-1:0] t_b_re,
        input logic signed [H_W-1:0] t_b_im,
        input logic signed [ACC_W-1:0] exp_re,
        input logic signed [ACC_W-1:0] exp_im
    );
        begin
            a_re = t_a_re;
            a_im = t_a_im;
            b_re = t_b_re;
            b_im = t_b_im;
            #1;

            if (y_re !== exp_re || y_im !== exp_im) begin
                $display("FAIL:");
                $display("a=(%0d,%0d), b=(%0d,%0d)", t_a_re, t_a_im, t_b_re, t_b_im);
                $display("got      y=(%0d,%0d)", y_re, y_im);
                $display("expected y=(%0d,%0d)", exp_re, exp_im);
                $fatal;
            end
            else begin
                $display("PASS: a=(%0d,%0d), b=(%0d,%0d), y=(%0d,%0d)",
                         t_a_re, t_a_im, t_b_re, t_b_im, y_re, y_im);
            end
        end
    endtask

    initial begin
        $display("Starting tb_complex_mult");

        // 1.0 * 1.0 = 1.0
        check_mult(
            16'sd4096, 16'sd0,
            16'sd4096, 16'sd0,
            28'sd65536, 28'sd0
        );

        // j * j = -1
        check_mult(
            16'sd0, 16'sd4096,
            16'sd0, 16'sd4096,
            -28'sd65536, 28'sd0
        );

        // (1+j)*(1-j) = 2 + 0j
        check_mult(
            16'sd4096, 16'sd4096,
            16'sd4096, -16'sd4096,
            28'sd131072, 28'sd0
        );

        // (0.5 + 0.5j)*(0.5 + 0.5j) = 0 + 0.5j
        // 0.5 in Q4.12 = 2048
        // 0.5 in Q12.16 = 32768
        check_mult(
            16'sd2048, 16'sd2048,
            16'sd2048, 16'sd2048,
            28'sd0, 28'sd32768
        );

        $display("tb_complex_mult PASSED");
        $finish;
    end

endmodule