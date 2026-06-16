`timescale 1ns/1ps

module tb_uart_rx_tx;

    localparam int CLKS_PER_BIT = 8;
    localparam int CLK_PERIOD_NS = 10;
    localparam int NUM_TESTS = 5;

    logic clk;
    logic rst_n;
    logic tx_start;
    logic [7:0] tx_data;
    logic tx_busy;
    logic tx_done;
    logic tx_line;
    logic rx_valid;
    logic [7:0] rx_data;

    logic [7:0] test_bytes [0:NUM_TESTS-1];

    int errors;
    int rx_valid_pulses;
    int tx_done_pulses;
    logic rx_valid_d;
    logic tx_done_d;

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .tx(tx_line)
    );

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx(tx_line),
        .rx_valid(rx_valid),
        .rx_data(rx_data)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_valid_pulses <= 0;
            tx_done_pulses <= 0;
            rx_valid_d <= 1'b0;
            tx_done_d <= 1'b0;
        end else begin
            rx_valid_d <= rx_valid;
            tx_done_d <= tx_done;

            if (rx_valid && !rx_valid_d) begin
                rx_valid_pulses <= rx_valid_pulses + 1;
            end

            if (tx_done && !tx_done_d) begin
                tx_done_pulses <= tx_done_pulses + 1;
            end

            if (rx_valid && rx_valid_d) begin
                $display("FAIL: rx_valid stayed high for more than one clock");
                errors <= errors + 1;
            end

            if (tx_done && tx_done_d) begin
                $display("FAIL: tx_done stayed high for more than one clock");
                errors <= errors + 1;
            end
        end
    end

    task automatic send_and_check(input int idx, input logic [7:0] expected);
        int start_rx_pulses;
        int start_tx_pulses;
        int timeout;
        logic [7:0] received;
        begin
            start_rx_pulses = rx_valid_pulses;
            start_tx_pulses = tx_done_pulses;
            received = 8'hxx;

            @(negedge clk);
            tx_data = expected;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;

            timeout = CLKS_PER_BIT * 16;
            while ((rx_valid_pulses == start_rx_pulses) && (timeout > 0)) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("FAIL: byte %0d expected 0x%02h but rx_valid never asserted", idx, expected);
                errors = errors + 1;
            end else begin
                received = rx_data;
                if (received !== expected) begin
                    $display("FAIL: byte %0d mismatch expected 0x%02h got 0x%02h", idx, expected, received);
                    errors = errors + 1;
                end else begin
                    $display("PASS: byte %0d matched 0x%02h", idx, expected);
                end
            end

            timeout = CLKS_PER_BIT * 4;
            while ((tx_done_pulses == start_tx_pulses) && (timeout > 0)) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("FAIL: byte %0d expected 0x%02h but tx_done never asserted", idx, expected);
                errors = errors + 1;
            end

            repeat (CLKS_PER_BIT) @(posedge clk);

            if ((rx_valid_pulses - start_rx_pulses) != 1) begin
                $display(
                    "FAIL: byte %0d expected one rx_valid pulse, saw %0d",
                    idx,
                    rx_valid_pulses - start_rx_pulses
                );
                errors = errors + 1;
            end

            if ((tx_done_pulses - start_tx_pulses) != 1) begin
                $display(
                    "FAIL: byte %0d expected one tx_done pulse, saw %0d",
                    idx,
                    tx_done_pulses - start_tx_pulses
                );
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        int i;

        test_bytes[0] = 8'h00;
        test_bytes[1] = 8'h55;
        test_bytes[2] = 8'ha5;
        test_bytes[3] = 8'hff;
        test_bytes[4] = 8'h5a;

        rst_n = 1'b0;
        tx_start = 1'b0;
        tx_data = 8'h00;
        errors = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            send_and_check(i, test_bytes[i]);
        end

        repeat (5) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: UART TX/RX loopback matched all %0d bytes", NUM_TESTS);
            $finish;
        end else begin
            $display("FAIL: UART TX/RX loopback completed with %0d error(s)", errors);
            $stop;
        end
    end

endmodule
