`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_gram_matrix_compute;

    import fixed_point_pkg::*;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];

    logic signed [GBW_W-1:0] G_re [NT][NT];
    logic signed [GBW_W-1:0] G_im [NT][NT];

    gram_matrix_compute dut (
        .H_re(H_re),
        .H_im(H_im),
        .G_re(G_re),
        .G_im(G_im)
    );

    task clear_H;
        begin
            for (int r = 0; r < NR; r++) begin
                for (int c = 0; c < NT; c++) begin
                    H_re[r][c] = '0;
                    H_im[r][c] = '0;
                end
            end
        end
    endtask

    initial begin
        $display("Starting tb_gram_matrix_compute");

        clear_H();

        // H = identity
        for (int i = 0; i < NT; i++) begin
            H_re[i][i] = 16'sd4096;
        end

        #1;

        for (int i = 0; i < NT; i++) begin
            for (int j = 0; j < NT; j++) begin
                if (i == j) begin
                    if (G_re[i][j] !== 20'sd4096 || G_im[i][j] !== 20'sd0) begin
                        $display("FAIL diag G[%0d][%0d] = (%0d,%0d), expected (4096,0)",
                                 i, j, G_re[i][j], G_im[i][j]);
                        $fatal;
                    end
                end
                else begin
                    if (G_re[i][j] !== 20'sd0 || G_im[i][j] !== 20'sd0) begin
                        $display("FAIL offdiag G[%0d][%0d] = (%0d,%0d), expected (0,0)",
                                 i, j, G_re[i][j], G_im[i][j]);
                        $fatal;
                    end
                end
            end
        end

        $display("PASS: Gram matrix identity test");
        $display("tb_gram_matrix_compute PASSED");
        $finish;
    end

endmodule