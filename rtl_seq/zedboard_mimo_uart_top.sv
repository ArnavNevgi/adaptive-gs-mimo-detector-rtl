`include "fixed_point_pkg.sv"

module zedboard_mimo_uart_top (
    input  logic clk,
    input  logic rst_btn,
    input  logic uart_rx_i,

    output logic uart_tx_o,
    output logic [7:0] led
);

    import fixed_point_pkg::*;

    localparam int UART_CLKS_PER_BIT = 434;

    logic clk_ibuf;
    logic clk_feedback;
    logic clk_feedback_buf;
    logic clk_50_unbuf;
    logic clk_50;
    logic mmcm_locked;

    IBUF u_clk_ibuf (
        .I(clk),
        .O(clk_ibuf)
    );

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKIN1_PERIOD(10.000),
        .CLKOUT0_DIVIDE_F(20.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE(0.000),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm_100_to_50 (
        .CLKIN1(clk_ibuf),
        .CLKFBIN(clk_feedback_buf),
        .CLKFBOUT(clk_feedback),
        .CLKFBOUTB(),
        .CLKOUT0(clk_50_unbuf),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(mmcm_locked),
        .PWRDWN(1'b0),
        .RST(rst_btn)
    );

    BUFG u_clk_feedback_buf (
        .I(clk_feedback),
        .O(clk_feedback_buf)
    );

    BUFG u_clk_50_buf (
        .I(clk_50_unbuf),
        .O(clk_50)
    );

    (* ASYNC_REG = "TRUE" *) logic [2:0] rst_sync;
    logic rst_active;
    logic rst_n;

    always_ff @(posedge clk_50 or negedge mmcm_locked) begin
        if (!mmcm_locked) begin
            rst_sync <= 3'b111;
        end else begin
            rst_sync <= {rst_sync[1:0], rst_btn};
        end
    end

    assign rst_active = rst_sync[2];
    assign rst_n = !rst_active;

    logic rx_valid;
    logic [7:0] rx_data;
    logic tx_start;
    logic [7:0] tx_data;
    logic tx_busy;

    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_rx (
        .clk(clk_50),
        .rst_n(rst_n),
        .rx(uart_rx_i),
        .rx_valid(rx_valid),
        .rx_data(rx_data)
    );

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk_50),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx(uart_tx_o)
    );

    logic detector_start;
    logic [1:0] snr_level;
    logic signed [GBW_W-1:0] noise_var;
    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];
    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    logic detector_done;
    logic detector_busy;
    gs_mode_t detector_mode;
    logic [4:0] detector_num_iters;
    logic [1:0] detector_bits [NT];
    logic signed [XOUT_W-1:0] detector_xout_re [NT];
    logic signed [XOUT_W-1:0] detector_xout_im [NT];

    logic protocol_rx_activity;
    logic done_latched;
    logic [2:0] last_status;
    logic [1:0] last_mode;

    uart_mimo_protocol u_uart_mimo_protocol (
        .clk(clk_50),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_data(rx_data),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .detector_start(detector_start),
        .snr_level(snr_level),
        .noise_var(noise_var),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .detector_done(detector_done),
        .detector_busy(detector_busy),
        .detector_mode(detector_mode),
        .detector_num_iters(detector_num_iters),
        .detector_bits(detector_bits),
        .detector_xout_re(detector_xout_re),
        .detector_xout_im(detector_xout_im),
        .rx_activity(protocol_rx_activity),
        .done_latched(done_latched),
        .last_status(last_status),
        .last_mode(last_mode)
    );

    mimo_detector_top_seq u_mimo_detector_top_seq (
        .clk(clk_50),
        .rst_n(rst_n),
        .start(detector_start),
        .snr_level(snr_level),
        .noise_var(noise_var),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .done(detector_done),
        .busy(detector_busy),
        .mode(detector_mode),
        .num_iters(detector_num_iters),
        .bits(detector_bits),
        .xout_re(detector_xout_re),
        .xout_im(detector_xout_im)
    );

    logic [25:0] heartbeat_cnt;
    logic [19:0] rx_activity_cnt;

    always_ff @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            heartbeat_cnt <= '0;
            rx_activity_cnt <= '0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1'b1;

            if (protocol_rx_activity) begin
                rx_activity_cnt <= '1;
            end else if (rx_activity_cnt != '0) begin
                rx_activity_cnt <= rx_activity_cnt - 1'b1;
            end
        end
    end

    always_comb begin
        led = '0;

        if (mmcm_locked) begin
            led[0] = heartbeat_cnt[25];
            led[1] = (rx_activity_cnt != '0);
            led[2] = detector_busy;
            led[3] = done_latched;
            led[5:4] = last_mode;
            led[7:6] = (last_status == 3'd0) ? 2'b00 :
                       (last_status == 3'd4) ? 2'b11 :
                       last_status[1:0];
        end
    end

endmodule
