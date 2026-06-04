`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_regularization_unit;

    import fixed_point_pkg::*;

    logic signed [GBW_W-1:0] G_re [NT][NT];
    logic signed [GBW_W-1:0] G_im [NT][NT];

    logic signed [GBW_W-1:0] W_re [NT][NT];
    logic signed [GBW_W-1:0] W_im [NT][NT];

    logic signed [GBW_W-1:0] noise_var;

    regularization_unit dut (
        .G_re(G_re),
        .G_im(G_im),
        .noise_var(noise_var),
        .W_re(W_re),
        .W_im(W_im)
    );

    initial begin
        $display("Starting tb_regularization_unit");

        noise_var = 20'sd512; // 0.125 in Q8.12

        for (int i = 0; i < NT; i++) begin
            for (int j = 0; j < NT; j++) begin
                G_re[i][j] = 20'sd100;
                G_im[i][j] = 20'sd20;
            end
        end

        #1;

        for (int i = 0; i < NT; i++) begin
            for (int j = 0; j < NT; j++) begin
                if (i == j) begin
                    if (W_re[i][j] !== 20'sd612 || W_im[i][j] !== 20'sd20) begin
                        $display("FAIL diag W[%0d][%0d] = (%0d,%0d), expected (612,20)",
                                 i, j, W_re[i][j], W_im[i][j]);
                        $fatal;
                    end
                end
                else begin
                    if (W_re[i][j] !== 20'sd100 || W_im[i][j] !== 20'sd20) begin
                        $display("FAIL offdiag W[%0d][%0d] = (%0d,%0d), expected (100,20)",
                                 i, j, W_re[i][j], W_im[i][j]);
                        $fatal;
                    end
                end
            end
        end

        $display("PASS: regularization test");
        $display("tb_regularization_unit PASSED");
        $finish;
    end

endmodule