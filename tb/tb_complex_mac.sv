`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_complex_mac;

    import fixed_point_pkg::*;

    logic signed [H_W-1:0] a_re;
    logic signed [H_W-1:0] a_im;
    logic signed [H_W-1:0] b_re;
    logic signed [H_W-1:0] b_im;

    logic signed [ACC_W-1:0] acc_in_re;
    logic signed [ACC_W-1:0] acc_in_im;
    logic signed [ACC_W-1:0] acc_out_re;
    logic signed [ACC_W-1:0] acc_out_im;

    complex_mac #(
        .A_W(H_W),
        .A_FRAC(H_FRAC),
        .B_W(H_W),
        .B_FRAC(H_FRAC),
        .ACC_W(ACC_W),
        .ACC_FRAC(ACC_FRAC)
    ) dut (
        .a_re(a_re),
        .a_im(a_im),
        .b_re(b_re),
        .b_im(b_im),
        .acc_in_re(acc_in_re),
        .acc_in_im(acc_in_im),
        .acc_out_re(acc_out_re),
        .acc_out_im(acc_out_im)
    );

    task check_mac(
        input logic signed [H_W-1:0] t_a_re,
        input logic signed [H_W-1:0] t_a_im,
        input logic signed [H_W-1:0] t_b_re,
        input logic signed [H_W-1:0] t_b_im,
        input logic signed [ACC_W-1:0] t_acc_re,
        input logic signed [ACC_W-1:0] t_acc_im,
        input logic signed [ACC_W-1:0] exp_re,
        input logic signed [ACC_W-1:0] exp_im
    );
        begin
            a_re      = t_a_re;
            a_im      = t_a_im;
            b_re      = t_b_re;
            b_im      = t_b_im;
            acc_in_re = t_acc_re;
            acc_in_im = t_acc_im;
            #1;

            if (acc_out_re !== exp_re || acc_out_im !== exp_im) begin
                $display("FAIL MAC");
                $display("got      = (%0d,%0d)", acc_out_re, acc_out_im);
                $display("expected = (%0d,%0d)", exp_re, exp_im);
                $fatal;
            end
            else begin
                $display("PASS MAC: out=(%0d,%0d)", acc_out_re, acc_out_im);
            end
        end
    endtask

    initial begin
        $display("Starting tb_complex_mac");

        // 1*1 + 0 = 1
        check_mac(
            16'sd4096, 16'sd0,
            16'sd4096, 16'sd0,
            28'sd0, 28'sd0,
            28'sd65536, 28'sd0
        );

        // j*j + 1 = -1 + 1 = 0
        check_mac(
            16'sd0, 16'sd4096,
            16'sd0, 16'sd4096,
            28'sd65536, 28'sd0,
            28'sd0, 28'sd0
        );

        // (0.5+0.5j)^2 + (1+0j) = 1 + 0.5j
        check_mac(
            16'sd2048, 16'sd2048,
            16'sd2048, 16'sd2048,
            28'sd65536, 28'sd0,
            28'sd65536, 28'sd32768
        );

        $display("tb_complex_mac PASSED");
        $finish;
    end

endmodule