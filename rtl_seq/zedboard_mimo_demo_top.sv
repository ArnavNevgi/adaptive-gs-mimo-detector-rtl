`include "fixed_point_pkg.sv"

// Minimal ZedBoard demo wrapper for the verified sequential MIMO detector.
//
// SW1 selects the LED page:
//   0: status page, LD0=done, LD1=busy, LD3:LD2=mode, LD4=heartbeat
//   1: detected bits page, LD(2*i+1):LD(2*i)=bits[i] for stream i
module zedboard_mimo_demo_top (
    input  logic clk,
    input  logic rst_btn,
    input  logic start_btn,
    input  logic start_sw,
    input  logic display_sw,

    output logic [7:0] led
);

    import fixed_point_pkg::*;

    localparam logic signed [H_W-1:0] H_ONE     = 16'sd4096;
    localparam logic signed [Y_W-1:0] Y_ONE     = 16'sd4096;
    localparam logic signed [Y_W-1:0] Y_NEG_ONE = -16'sd4096;

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
    (* ASYNC_REG = "TRUE" *) logic [2:0] start_btn_sync;
    (* ASYNC_REG = "TRUE" *) logic [2:0] start_sw_sync;
    (* ASYNC_REG = "TRUE" *) logic [2:0] display_sw_sync;

    logic rst_active;
    logic core_rst_n;
    logic start_level;
    logic start_level_d;
    logic start_pulse;
    logic display_bits_page;

    always_ff @(posedge clk_50 or negedge mmcm_locked) begin
        if (!mmcm_locked) begin
            rst_sync <= 3'b111;
        end else begin
            rst_sync <= {rst_sync[1:0], rst_btn};
        end
    end

    assign rst_active = rst_sync[2];
    assign core_rst_n = !rst_active;

    always_ff @(posedge clk_50 or negedge core_rst_n) begin
        if (!core_rst_n) begin
            start_btn_sync <= '0;
            start_sw_sync <= '0;
            display_sw_sync <= '0;
        end else begin
            start_btn_sync <= {start_btn_sync[1:0], start_btn};
            start_sw_sync <= {start_sw_sync[1:0], start_sw};
            display_sw_sync <= {display_sw_sync[1:0], display_sw};
        end
    end

    assign start_level = start_btn_sync[2] | start_sw_sync[2];
    assign display_bits_page = display_sw_sync[2];

    logic [1:0] snr_level;
    logic signed [GBW_W-1:0] noise_var;
    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];
    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    logic core_done;
    logic core_busy;
    gs_mode_t core_mode;
    logic [4:0] core_num_iters;
    logic [1:0] core_bits [NT];
    logic signed [XOUT_W-1:0] core_xout_re [NT];
    logic signed [XOUT_W-1:0] core_xout_im [NT];

    gs_mode_t mode_latched;
    logic [4:0] num_iters_latched;
    logic [1:0] bits_latched [NT];
    logic done_latched;
    logic [25:0] heartbeat_cnt;

    always_comb begin
        snr_level = 2'd2;
        noise_var = '0;

        for (int r = 0; r < NR; r++) begin
            y_re[r] = '0;
            y_im[r] = '0;

            for (int c = 0; c < NT; c++) begin
                H_re[r][c] = '0;
                H_im[r][c] = '0;
            end
        end

        H_re[0][0] = H_ONE;
        H_re[1][1] = H_ONE;
        H_re[2][2] = H_ONE;
        H_re[3][3] = H_ONE;

        y_re[0] = Y_ONE;
        y_im[0] = Y_ONE;
        y_re[1] = Y_NEG_ONE;
        y_im[1] = Y_ONE;
        y_re[2] = Y_NEG_ONE;
        y_im[2] = Y_NEG_ONE;
        y_re[3] = Y_ONE;
        y_im[3] = Y_NEG_ONE;
    end

    always_ff @(posedge clk_50 or negedge core_rst_n) begin
        if (!core_rst_n) begin
            start_level_d <= 1'b0;
            start_pulse <= 1'b0;
            heartbeat_cnt <= '0;
            done_latched <= 1'b0;
            mode_latched <= MODE_GS4;
            num_iters_latched <= '0;

            for (int i = 0; i < NT; i++) begin
                bits_latched[i] <= '0;
            end
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1'b1;
            start_level_d <= start_level;
            start_pulse <= start_level & !start_level_d & !core_busy;

            if (start_pulse) begin
                done_latched <= 1'b0;
            end

            if (core_done) begin
                done_latched <= 1'b1;
                mode_latched <= core_mode;
                num_iters_latched <= core_num_iters;

                for (int i = 0; i < NT; i++) begin
                    bits_latched[i] <= core_bits[i];
                end
            end
        end
    end

    mimo_detector_top_seq #(
        .NR(NR),
        .NT(NT)
    ) u_mimo_detector_top_seq (
        .clk(clk_50),
        .rst_n(core_rst_n),
        .start(start_pulse),
        .snr_level(snr_level),
        .noise_var(noise_var),
        .H_re(H_re),
        .H_im(H_im),
        .y_re(y_re),
        .y_im(y_im),
        .done(core_done),
        .busy(core_busy),
        .mode(core_mode),
        .num_iters(core_num_iters),
        .bits(core_bits),
        .xout_re(core_xout_re),
        .xout_im(core_xout_im)
    );

    logic [7:0] status_led;
    logic [7:0] bits_led;

    always_comb begin
        status_led = '0;
        status_led[0] = done_latched;
        status_led[1] = core_busy;
        status_led[3:2] = mode_latched;
        status_led[4] = heartbeat_cnt[25];

        bits_led = '0;
        for (int i = 0; i < NT; i++) begin
            bits_led[i*2 +: 2] = bits_latched[i];
        end

        if (!mmcm_locked) begin
            led = 8'h00;
        end else if (display_bits_page) begin
            led = bits_led;
        end else begin
            led = status_led;
        end
    end

endmodule
