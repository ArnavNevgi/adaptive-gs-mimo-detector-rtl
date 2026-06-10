`include "fixed_point_pkg.sv"

// Implementation-facing wrapper for package-level place-and-route.
//
// The synthesis wrapper intentionally exposes the full flattened detector
// vectors, which is useful for OOC synthesis but creates 810 top-level I/O
// ports. That cannot be placed in the xc7a35tcpg236 package. This wrapper keeps
// the verified sequential detector core intact and exposes a compact host-style
// register interface for implementation experiments and bitstream generation.
//
// Write address map:
//   0        noise_var[19:0]
//   1        snr_level[1:0]
//   2..17    H_re[r][c], index = addr - 2,  r = index / NT, c = index % NT
//   18..33   H_im[r][c], index = addr - 18
//   34..37   y_re[r],    r = addr - 34
//   38..41   y_im[r],    r = addr - 38
//
// Read address map:
//   0        {8'd0, num_iters[4:0], mode[1:0], busy, done}
//   1        noise_var[19:0]
//   2        {18'd0, snr_level[1:0]}
//   10..13   {18'd0, bits[i]}
//   20..23   sign-extended xout_re[i]
//   24..27   sign-extended xout_im[i]
module mimo_detector_top_seq_impl_wrapper #(
    parameter int NR = fixed_point_pkg::NR,
    parameter int NT = fixed_point_pkg::NT
) (
    input  logic clk,
    input  logic rst_n,

    input  logic start,

    input  logic host_wr_en,
    input  logic [5:0] host_wr_addr,
    input  logic [fixed_point_pkg::GBW_W-1:0] host_wr_data,

    input  logic [5:0] host_rd_addr,
    output logic [fixed_point_pkg::GBW_W-1:0] host_rd_data,

    output logic done,
    output logic busy,
    output logic [1:0] mode,
    output logic [4:0] num_iters
);

    import fixed_point_pkg::*;

    logic [1:0] snr_level;
    logic signed [GBW_W-1:0] noise_var;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];
    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    gs_mode_t mode_internal;
    logic [1:0] bits [NT];
    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

    assign mode = mode_internal;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snr_level <= '0;
            noise_var <= '0;

            for (int r = 0; r < NR; r++) begin
                y_re[r] <= '0;
                y_im[r] <= '0;

                for (int c = 0; c < NT; c++) begin
                    H_re[r][c] <= '0;
                    H_im[r][c] <= '0;
                end
            end
        end else if (host_wr_en) begin
            if (host_wr_addr == 6'd0) begin
                noise_var <= host_wr_data;
            end else if (host_wr_addr == 6'd1) begin
                snr_level <= host_wr_data[1:0];
            end else if ((host_wr_addr >= 6'd2) && (host_wr_addr <= 6'd17)) begin
                H_re[(host_wr_addr - 6'd2) / NT][(host_wr_addr - 6'd2) % NT] <= host_wr_data[H_W-1:0];
            end else if ((host_wr_addr >= 6'd18) && (host_wr_addr <= 6'd33)) begin
                H_im[(host_wr_addr - 6'd18) / NT][(host_wr_addr - 6'd18) % NT] <= host_wr_data[H_W-1:0];
            end else if ((host_wr_addr >= 6'd34) && (host_wr_addr <= 6'd37)) begin
                y_re[host_wr_addr - 6'd34] <= host_wr_data[Y_W-1:0];
            end else if ((host_wr_addr >= 6'd38) && (host_wr_addr <= 6'd41)) begin
                y_im[host_wr_addr - 6'd38] <= host_wr_data[Y_W-1:0];
            end
        end
    end

    always_comb begin
        host_rd_data = '0;

        if (host_rd_addr == 6'd0) begin
            host_rd_data = {{(GBW_W-9){1'b0}}, num_iters, mode_internal, busy, done};
        end else if (host_rd_addr == 6'd1) begin
            host_rd_data = noise_var;
        end else if (host_rd_addr == 6'd2) begin
            host_rd_data = {{(GBW_W-2){1'b0}}, snr_level};
        end else if ((host_rd_addr >= 6'd10) && (host_rd_addr <= 6'd13)) begin
            host_rd_data = {{(GBW_W-2){1'b0}}, bits[host_rd_addr - 6'd10]};
        end else if ((host_rd_addr >= 6'd20) && (host_rd_addr <= 6'd23)) begin
            host_rd_data = {{(GBW_W-XOUT_W){xout_re[host_rd_addr - 6'd20][XOUT_W-1]}}, xout_re[host_rd_addr - 6'd20]};
        end else if ((host_rd_addr >= 6'd24) && (host_rd_addr <= 6'd27)) begin
            host_rd_data = {{(GBW_W-XOUT_W){xout_im[host_rd_addr - 6'd24][XOUT_W-1]}}, xout_im[host_rd_addr - 6'd24]};
        end
    end

    mimo_detector_top_seq #(
        .NR(NR),
        .NT(NT)
    ) u_mimo_detector_top_seq (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .snr_level(snr_level),
        .noise_var(noise_var),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .done(done),
        .busy(busy),
        .mode(mode_internal),
        .num_iters(num_iters),
        .bits(bits),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

endmodule
