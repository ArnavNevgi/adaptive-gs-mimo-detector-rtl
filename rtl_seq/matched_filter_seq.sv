`include "fixed_point_pkg.sv"

module matched_filter_seq #(
    parameter int NR = fixed_point_pkg::NR,
    parameter int NT = fixed_point_pkg::NT
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  var logic signed [fixed_point_pkg::H_W-1:0] H_re [NR][NT],
    input  var logic signed [fixed_point_pkg::H_W-1:0] H_im [NR][NT],
    input  var logic signed [fixed_point_pkg::Y_W-1:0] y_re [NR],
    input  var logic signed [fixed_point_pkg::Y_W-1:0] y_im [NR],

    output logic done,
    output logic busy,

    output logic signed [fixed_point_pkg::GBW_W-1:0] b_re [NT],
    output logic signed [fixed_point_pkg::GBW_W-1:0] b_im [NT]
);

    import fixed_point_pkg::*;

    typedef enum logic [1:0] {
        S_IDLE,
        S_INIT_ENTRY,
        S_ACCUM,
        S_WRITE
    } state_t;

    state_t state, state_n;

    logic [$clog2(NT)-1:0] i_idx;
    logic [$clog2(NR)-1:0] r_idx;

    logic [$clog2(NT)-1:0] i_idx_n;
    logic [$clog2(NR)-1:0] r_idx_n;

    logic signed [ACC_W-1:0] acc_re;
    logic signed [ACC_W-1:0] acc_im;
    logic signed [ACC_W-1:0] acc_re_n;
    logic signed [ACC_W-1:0] acc_im_n;

    logic done_n;
    logic busy_n;

    // Product intermediates.
    // H and y are both Q4.12 in this project.
    // Raw product scale is Q8.24.
    localparam int PROD_W = H_W + Y_W;
    localparam int PROD_FRAC = H_FRAC + Y_FRAC;
    localparam int SHIFT_TO_ACC = PROD_FRAC - ACC_FRAC;
    localparam int SHIFT_TO_OUT = ACC_FRAC - GBW_FRAC;

    logic signed [PROD_W-1:0] ac;
    logic signed [PROD_W-1:0] bd;
    logic signed [PROD_W-1:0] ad;
    logic signed [PROD_W-1:0] bc;

    logic signed [PROD_W:0] prod_re_full;
    logic signed [PROD_W:0] prod_im_full;

    logic signed [ACC_W-1:0] prod_re_scaled;
    logic signed [ACC_W-1:0] prod_im_scaled;

    // conj(H[r][i]) * y[r]
    //
    // If H[r][i] = a + jb
    // and y[r]    = c + jd
    //
    // conj(H[r][i]) * y[r]
    // = (a - jb)(c + jd)
    // = (ac + bd) + j(ad - bc)

    function automatic logic signed [ACC_W-1:0] product_to_acc(
        input logic signed [PROD_W:0] value
    );
        begin
            if (SHIFT_TO_ACC >= 0)
                product_to_acc = value >>> SHIFT_TO_ACC;
            else
                product_to_acc = value <<< (-SHIFT_TO_ACC);
        end
    endfunction

    function automatic logic signed [GBW_W-1:0] acc_to_gbw(
        input logic signed [ACC_W-1:0] value
    );
        begin
            if (SHIFT_TO_OUT >= 0)
                acc_to_gbw = value >>> SHIFT_TO_OUT;
            else
                acc_to_gbw = value <<< (-SHIFT_TO_OUT);
        end
    endfunction

    always_comb begin
        ac = H_re[r_idx][i_idx] * y_re[r_idx];
        bd = H_im[r_idx][i_idx] * y_im[r_idx];
        ad = H_re[r_idx][i_idx] * y_im[r_idx];
        bc = H_im[r_idx][i_idx] * y_re[r_idx];

        prod_re_full = $signed(ac) + $signed(bd);
        prod_im_full = $signed(ad) - $signed(bc);

        // Match rtl/matched_filter_compute.sv: truncate each product to
        // ACC_FRAC, accumulate, then truncate the final accumulator to GBW_FRAC.
        prod_re_scaled = product_to_acc(prod_re_full);
        prod_im_scaled = product_to_acc(prod_im_full);
    end

    always_comb begin
        state_n  = state;

        i_idx_n  = i_idx;
        r_idx_n  = r_idx;

        acc_re_n = acc_re;
        acc_im_n = acc_im;

        done_n   = 1'b0;
        busy_n   = busy;

        case (state)
            S_IDLE: begin
                busy_n = 1'b0;
                done_n = 1'b0;

                if (start) begin
                    busy_n   = 1'b1;
                    i_idx_n  = '0;
                    r_idx_n  = '0;
                    acc_re_n = '0;
                    acc_im_n = '0;
                    state_n  = S_INIT_ENTRY;
                end
            end

            S_INIT_ENTRY: begin
                acc_re_n = '0;
                acc_im_n = '0;
                r_idx_n  = '0;
                state_n  = S_ACCUM;
            end

            S_ACCUM: begin
                acc_re_n = acc_re + prod_re_scaled;
                acc_im_n = acc_im + prod_im_scaled;

                if (r_idx == NR-1) begin
                    state_n = S_WRITE;
                end else begin
                    r_idx_n = r_idx + 1'b1;
                end
            end

            S_WRITE: begin
                if (i_idx == NT-1) begin
                    i_idx_n = '0;
                    busy_n  = 1'b0;
                    done_n  = 1'b1;
                    state_n = S_IDLE;
                end else begin
                    i_idx_n = i_idx + 1'b1;
                    state_n = S_INIT_ENTRY;
                end
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    integer ii;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;

            i_idx  <= '0;
            r_idx  <= '0;

            acc_re <= '0;
            acc_im <= '0;

            done   <= 1'b0;
            busy   <= 1'b0;

            for (ii = 0; ii < NT; ii++) begin
                b_re[ii] <= '0;
                b_im[ii] <= '0;
            end
        end else begin
            state  <= state_n;

            i_idx  <= i_idx_n;
            r_idx  <= r_idx_n;

            acc_re <= acc_re_n;
            acc_im <= acc_im_n;

            done   <= done_n;
            busy   <= busy_n;

            if (state == S_WRITE) begin
                b_re[i_idx] <= acc_to_gbw(acc_re);
                b_im[i_idx] <= acc_to_gbw(acc_im);
            end
        end
    end

endmodule
