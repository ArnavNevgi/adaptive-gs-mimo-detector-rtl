// Sequential signed divider for timing-friendly synthesis.
//
// The quotient width matches NUM_W, which mirrors SystemVerilog division where
// the wider numerator in gs_solver_seq determines the quotient expression size.
// Divide-by-zero returns zero, matching the old div_q_to_x() helper.
module signed_divider_seq #(
    parameter int NUM_W = 56,
    parameter int DEN_W = 20
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  logic signed [NUM_W-1:0] numerator,
    input  logic signed [DEN_W-1:0] denominator,

    output logic done,
    output logic busy,
    output logic signed [NUM_W-1:0] quotient
);

    localparam int IDX_W = (NUM_W <= 1) ? 1 : $clog2(NUM_W);

    typedef enum logic {
        S_IDLE,
        S_RUN
    } state_t;

    state_t state;

    logic [IDX_W-1:0] bit_idx;
    logic result_negative;

    logic [NUM_W-1:0] dividend_abs;
    logic [NUM_W:0] divisor_abs_ext;
    logic [NUM_W:0] remainder;
    logic [NUM_W-1:0] quotient_abs;

    logic [NUM_W:0] remainder_shift;
    logic [NUM_W:0] remainder_next;
    logic [NUM_W-1:0] quotient_abs_next;
    logic signed [NUM_W-1:0] quotient_signed_next;

    function automatic logic [NUM_W-1:0] abs_num(
        input logic signed [NUM_W-1:0] value
    );
        begin
            if (value[NUM_W-1])
                abs_num = (~value) + {{(NUM_W-1){1'b0}}, 1'b1};
            else
                abs_num = value;
        end
    endfunction

    function automatic logic [DEN_W-1:0] abs_den(
        input logic signed [DEN_W-1:0] value
    );
        begin
            if (value[DEN_W-1])
                abs_den = (~value) + {{(DEN_W-1){1'b0}}, 1'b1};
            else
                abs_den = value;
        end
    endfunction

    function automatic logic signed [NUM_W-1:0] apply_quotient_sign(
        input logic [NUM_W-1:0] magnitude,
        input logic negative
    );
        logic [NUM_W-1:0] signed_bits;
        begin
            if (negative)
                signed_bits = (~magnitude) + {{(NUM_W-1){1'b0}}, 1'b1};
            else
                signed_bits = magnitude;

            apply_quotient_sign = signed_bits;
        end
    endfunction

    always_comb begin
        remainder_shift = {remainder[NUM_W-1:0], dividend_abs[bit_idx]};
        quotient_abs_next = quotient_abs;

        if (remainder_shift >= divisor_abs_ext) begin
            remainder_next = remainder_shift - divisor_abs_ext;
            quotient_abs_next[bit_idx] = 1'b1;
        end else begin
            remainder_next = remainder_shift;
            quotient_abs_next[bit_idx] = 1'b0;
        end

        quotient_signed_next = apply_quotient_sign(quotient_abs_next, result_negative);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            bit_idx <= '0;
            result_negative <= 1'b0;

            dividend_abs <= '0;
            divisor_abs_ext <= '0;
            remainder <= '0;
            quotient_abs <= '0;
            quotient <= '0;

            done <= 1'b0;
            busy <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        if (denominator == '0) begin
                            quotient <= '0;
                            done <= 1'b1;
                        end else begin
                            dividend_abs <= abs_num(numerator);
                            divisor_abs_ext <= {{(NUM_W+1-DEN_W){1'b0}}, abs_den(denominator)};
                            remainder <= '0;
                            quotient_abs <= '0;
                            result_negative <= numerator[NUM_W-1] ^ denominator[DEN_W-1];
                            bit_idx <= NUM_W - 1;
                            busy <= 1'b1;
                            state <= S_RUN;
                        end
                    end
                end

                S_RUN: begin
                    remainder <= remainder_next;
                    quotient_abs <= quotient_abs_next;

                    if (bit_idx == '0) begin
                        quotient <= quotient_signed_next;
                        done <= 1'b1;
                        busy <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        bit_idx <= bit_idx - 1'b1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
