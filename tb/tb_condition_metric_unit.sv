`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_condition_metric_unit;

    import fixed_point_pkg::*;

    logic signed [GBW_W-1:0] G_re [NT][NT];
    logic signed [GBW_W-1:0] G_im [NT][NT];

    logic [31:0] diag_sum;
    logic [31:0] offdiag_sum;

    condition_metric_unit #(
        .N(NT),
        .IN_W(GBW_W),
        .METRIC_W(32)
    ) dut (
        .G_re(G_re),
        .G_im(G_im),
        .diag_sum(diag_sum),
        .offdiag_sum(offdiag_sum)
    );

    task clear_G;
        begin
            for (int i = 0; i < NT; i++) begin
                for (int j = 0; j < NT; j++) begin
                    G_re[i][j] = '0;
                    G_im[i][j] = '0;
                end
            end
        end
    endtask

    initial begin
        $display("Starting tb_condition_metric_unit");

        clear_G();

        // Diagonal entries:
        // G00 = 10 + j0 -> magnitude approx 10
        // G11 = 20 + j0 -> magnitude approx 20
        // G22 = -30 + j0 -> magnitude approx 30
        // G33 = 40 + j0 -> magnitude approx 40
        // diag_sum expected = 100

        G_re[0][0] = 20'sd10;
        G_re[1][1] = 20'sd20;
        G_re[2][2] = -20'sd30;
        G_re[3][3] = 20'sd40;

        // Off-diagonal:
        // G01 = 3 + j4 -> approx |3|+|4|=7
        // G10 = -5 + j2 -> approx 7
        // G23 = -1 - j9 -> approx 10
        // offdiag_sum expected = 24

        G_re[0][1] = 20'sd3;
        G_im[0][1] = 20'sd4;

        G_re[1][0] = -20'sd5;
        G_im[1][0] = 20'sd2;

        G_re[2][3] = -20'sd1;
        G_im[2][3] = -20'sd9;

        #1;

        if (diag_sum !== 32'd100) begin
            $display("FAIL: diag_sum got %0d expected 100", diag_sum);
            $fatal;
        end

        if (offdiag_sum !== 32'd24) begin
            $display("FAIL: offdiag_sum got %0d expected 24", offdiag_sum);
            $fatal;
        end

        $display("PASS: diag_sum=%0d offdiag_sum=%0d", diag_sum, offdiag_sum);
        $display("tb_condition_metric_unit PASSED");
        $finish;
    end

endmodule