`timescale 1ns/1ps

`include "../rtl/fixed_point_pkg.sv"

module tb_mode_select_unit;

    import fixed_point_pkg::*;

    logic [1:0] snr_level;
    logic [31:0] diag_sum;
    logic [31:0] offdiag_sum;

    gs_mode_t mode;
    logic [4:0] num_iters;

    mode_select_unit #(
        .METRIC_W(32)
    ) dut (
        .snr_level(snr_level),
        .diag_sum(diag_sum),
        .offdiag_sum(offdiag_sum),
        .mode(mode),
        .num_iters(num_iters)
    );

    task check_mode(
        input logic [1:0] t_snr_level,
        input logic [31:0] t_diag_sum,
        input logic [31:0] t_offdiag_sum,
        input gs_mode_t expected_mode,
        input logic [4:0] expected_iters
    );
        begin
            snr_level   = t_snr_level;
            diag_sum    = t_diag_sum;
            offdiag_sum = t_offdiag_sum;
            #1;

            if (mode !== expected_mode || num_iters !== expected_iters) begin
                $display("FAIL: snr=%0d diag=%0d offdiag=%0d mode=%0d iters=%0d expected mode=%0d iters=%0d",
                         t_snr_level, t_diag_sum, t_offdiag_sum,
                         mode, num_iters, expected_mode, expected_iters);
                $fatal;
            end
            else begin
                $display("PASS: snr=%0d diag=%0d offdiag=%0d mode=%0d iters=%0d",
                         t_snr_level, t_diag_sum, t_offdiag_sum,
                         mode, num_iters);
            end
        end
    endtask

    initial begin
        $display("Starting tb_mode_select_unit");

        // Low SNR: always GS-16, even if channel looks good.
        check_mode(2'd0, 200, 100, MODE_GS16, 5'd16);

        // Medium SNR, dominance >= 0.80:
        // 100*diag >= 80*offdiag
        // diag=80, offdiag=100 => 8000 >= 8000, GS-8
        check_mode(2'd1, 80, 100, MODE_GS8, 5'd8);

        // Medium SNR, weak dominance: GS-16
        // diag=70, offdiag=100 => 7000 < 8000
        check_mode(2'd1, 70, 100, MODE_GS16, 5'd16);

        // High SNR, dominance >= 1.05:
        // diag=105, offdiag=100 => 10500 >= 10500, GS-4
        check_mode(2'd2, 105, 100, MODE_GS4, 5'd4);

        // High SNR, not enough for GS-4 but enough for GS-8:
        // diag=90, offdiag=100 => not GS-4, but GS-8
        check_mode(2'd2, 90, 100, MODE_GS8, 5'd8);

        // High SNR, weak dominance: GS-16
        check_mode(2'd2, 70, 100, MODE_GS16, 5'd16);

        $display("tb_mode_select_unit PASSED");
        $finish;
    end

endmodule