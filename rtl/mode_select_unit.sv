// Inputs:

// snr_level:
//   0 = low SNR
//   1 = medium SNR, equivalent to snr >= 4
//   2 = high SNR, equivalent to snr >= 8

// RTL policy:

// if snr >= 8 and 100*diag_sum >= 105*offdiag_sum:
//     Mode 0 = GS-4
// elif snr >= 4 and 100*diag_sum >= 80*offdiag_sum:
//     Mode 1 = GS-8
// else:
//     Mode 2 = GS-16

`include "fixed_point_pkg.sv"

module mode_select_unit #(
    parameter int METRIC_W = 32
) (
    input  logic [1:0] snr_level,
    input  logic [METRIC_W-1:0] diag_sum,
    input  logic [METRIC_W-1:0] offdiag_sum,

    output fixed_point_pkg::gs_mode_t mode,
    output logic [4:0] num_iters
);

    logic [METRIC_W+7:0] lhs_100;
    logic [METRIC_W+7:0] rhs_105;
    logic [METRIC_W+7:0] rhs_80;

    always_comb begin
        lhs_100 = {8'd0, diag_sum} * 8'd100;
        rhs_105 = {8'd0, offdiag_sum} * 8'd105;
        rhs_80  = {8'd0, offdiag_sum} * 8'd80;

        if ((snr_level >= 2'd2) && (lhs_100 >= rhs_105)) begin
            mode = fixed_point_pkg::MODE_GS4;
            num_iters = 5'd4;
        end
        else if ((snr_level >= 2'd1) && (lhs_100 >= rhs_80)) begin
            mode = fixed_point_pkg::MODE_GS8;
            num_iters = 5'd8;
        end
        else begin
            mode = fixed_point_pkg::MODE_GS16;
            num_iters = 5'd16;
        end
    end

endmodule
