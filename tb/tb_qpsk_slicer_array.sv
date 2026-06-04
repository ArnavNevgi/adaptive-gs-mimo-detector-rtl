`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_qpsk_slicer_array;

    import fixed_point_pkg::*;

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

    logic [1:0] bits [NT];

    qpsk_slicer_array dut (
        .xout_re(xout_re),
        .xout_im(xout_im),
        .bits(bits)
    );

    task check_bits(
        input int idx,
        input logic [1:0] expected
    );
        begin
            if (bits[idx] !== expected) begin
                $display("FAIL bits[%0d]: got %b expected %b",
                         idx, bits[idx], expected);
                $fatal;
            end
            else begin
                $display("PASS bits[%0d] = %b", idx, bits[idx]);
            end
        end
    endtask

    initial begin
        $display("Starting tb_qpsk_slicer_array");

        // +re +im -> 00
        xout_re[0] = 16'sd4096;
        xout_im[0] = 16'sd4096;

        // -re +im -> 01
        xout_re[1] = -16'sd4096;
        xout_im[1] = 16'sd4096;

        // -re -im -> 11
        xout_re[2] = -16'sd4096;
        xout_im[2] = -16'sd4096;

        // +re -im -> 10
        xout_re[3] = 16'sd4096;
        xout_im[3] = -16'sd4096;

        #1;

        check_bits(0, 2'b00);
        check_bits(1, 2'b01);
        check_bits(2, 2'b11);
        check_bits(3, 2'b10);

        $display("tb_qpsk_slicer_array PASSED");
        $finish;
    end

endmodule