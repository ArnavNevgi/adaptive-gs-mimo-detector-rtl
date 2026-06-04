`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_qpsk_slicer;

    import fixed_point_pkg::*;

    logic signed [XOUT_W-1:0] x_re;
    logic signed [XOUT_W-1:0] x_im;

    logic bit0;
    logic bit1;

    qpsk_slicer #(
        .W(XOUT_W)
    ) dut (
        .x_re(x_re),
        .x_im(x_im),
        .bit0(bit0),
        .bit1(bit1)
    );

    task check_bits(
        input logic signed [XOUT_W-1:0] t_re,
        input logic signed [XOUT_W-1:0] t_im,
        input logic exp_bit0,
        input logic exp_bit1
    );
        begin
            x_re = t_re;
            x_im = t_im;
            #1;

            if (bit0 !== exp_bit0 || bit1 !== exp_bit1) begin
                $display("FAIL: re=%0d im=%0d got=%0b%0b expected=%0b%0b",
                         t_re, t_im, bit0, bit1, exp_bit0, exp_bit1);
                $fatal;
            end
            else begin
                $display("PASS: re=%0d im=%0d bits=%0b%0b",
                         t_re, t_im, bit0, bit1);
            end
        end
    endtask

    initial begin
        $display("Starting tb_qpsk_slicer");

        // bit0 = imag < 0
        // bit1 = real < 0

        check_bits(16'sd1000,  16'sd1000, 1'b0, 1'b0); // +re +im
        check_bits(-16'sd1000, 16'sd1000, 1'b0, 1'b1); // -re +im
        check_bits(-16'sd1000, -16'sd1000, 1'b1, 1'b1); // -re -im
        check_bits(16'sd1000, -16'sd1000, 1'b1, 1'b0); // +re -im

        $display("tb_qpsk_slicer PASSED");
        $finish;
    end

endmodule