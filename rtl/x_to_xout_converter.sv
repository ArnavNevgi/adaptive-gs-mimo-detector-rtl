`include "fixed_point_pkg.sv"

module x_to_xout_converter #(
    parameter int N          = fixed_point_pkg::NT,
    parameter int X_W        = fixed_point_pkg::X_W,
    parameter int X_FRAC     = fixed_point_pkg::X_FRAC,
    parameter int XOUT_W     = fixed_point_pkg::XOUT_W,
    parameter int XOUT_FRAC  = fixed_point_pkg::XOUT_FRAC
) (
    input  var logic signed [X_W-1:0]    x_re     [N],
    input  var logic signed [X_W-1:0]    x_im     [N],

    output logic signed [XOUT_W-1:0] xout_re  [N],
    output logic signed [XOUT_W-1:0] xout_im  [N]
);

    localparam int SHIFT = X_FRAC - XOUT_FRAC;

    localparam logic signed [63:0] XOUT_MAX = (64'sd1 <<< (XOUT_W-1)) - 1;
    localparam logic signed [63:0] XOUT_MIN = -(64'sd1 <<< (XOUT_W-1));

    function automatic logic signed [XOUT_W-1:0] convert_sat(
        input logic signed [X_W-1:0] value
    );
        logic signed [63:0] shifted;
        begin
            if (SHIFT >= 0)
                shifted = value >>> SHIFT;
            else
                shifted = value <<< (-SHIFT);

            if (shifted > XOUT_MAX)
                convert_sat = XOUT_MAX[XOUT_W-1:0];
            else if (shifted < XOUT_MIN)
                convert_sat = XOUT_MIN[XOUT_W-1:0];
            else
                convert_sat = shifted[XOUT_W-1:0];
        end
    endfunction

    always_comb begin
        for (int i = 0; i < N; i++) begin
            xout_re[i] = convert_sat(x_re[i]);
            xout_im[i] = convert_sat(x_im[i]);
        end
    end

endmodule
