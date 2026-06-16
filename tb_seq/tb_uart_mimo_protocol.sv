`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_uart_mimo_protocol;

    import fixed_point_pkg::*;

    localparam int RUN_VECTOR_PAYLOAD_BYTES = 85;
    localparam int OK_RESPONSE_BYTES = 28;
    localparam int ERROR_RESPONSE_BYTES = 6;
    localparam logic [15:0] RUN_VECTOR_PAYLOAD_LEN = 16'd85;
    localparam logic [15:0] BAD_PAYLOAD_LEN = 16'd84;

    logic clk;
    logic rst_n;

    logic rx_valid;
    logic [7:0] rx_data;
    logic tx_start;
    logic [7:0] tx_data;
    logic tx_busy;

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

    logic rx_activity;
    logic done_latched;
    logic [2:0] last_status;
    logic [1:0] last_mode;

    logic [7:0] payload [0:RUN_VECTOR_PAYLOAD_BYTES-1];
    logic [7:0] response [0:OK_RESPONSE_BYTES-1];
    int response_count;
    int errors;
    int tx_busy_countdown;

    uart_mimo_protocol dut (
        .clk(clk),
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
        .rx_activity(rx_activity),
        .done_latched(done_latched),
        .last_status(last_status),
        .last_mode(last_mode)
    );

    mimo_detector_top_seq u_mimo_detector_top_seq (
        .clk(clk),
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

    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_busy <= 1'b0;
            tx_busy_countdown <= 0;
            response_count <= 0;

            for (int i = 0; i < OK_RESPONSE_BYTES; i++) begin
                response[i] <= '0;
            end
        end else begin
            if (tx_start) begin
                if (response_count < OK_RESPONSE_BYTES) begin
                    response[response_count] <= tx_data;
                end
                response_count <= response_count + 1;
                tx_busy <= 1'b1;
                tx_busy_countdown <= 2;
            end else if (tx_busy_countdown > 0) begin
                tx_busy_countdown <= tx_busy_countdown - 1;
                tx_busy <= 1'b1;
            end else begin
                tx_busy <= 1'b0;
            end
        end
    end

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            rx_valid = 1'b0;
            rx_data = '0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (5) @(posedge clk);
        end
    endtask

    task automatic clear_response;
        begin
            response_count = 0;
            for (int i = 0; i < OK_RESPONSE_BYTES; i++) begin
                response[i] = '0;
            end
        end
    endtask

    task automatic set_s16(input int offset, input int value);
        begin
            payload[offset] = value[7:0];
            payload[offset + 1] = value[15:8];
        end
    endtask

    task automatic build_identity_payload;
        int idx;
        begin
            for (int i = 0; i < RUN_VECTOR_PAYLOAD_BYTES; i++) begin
                payload[i] = 8'h00;
            end

            payload[0] = 8'd2;
            payload[1] = 8'h00;
            payload[2] = 8'h00;
            payload[3] = 8'h00;
            payload[4] = 8'h00;

            for (int r = 0; r < NR; r++) begin
                for (int c = 0; c < NT; c++) begin
                    idx = r*NT + c;
                    set_s16(5 + 2*idx, (r == c) ? 4096 : 0);
                    set_s16(37 + 2*idx, 0);
                end
            end

            set_s16(69, 4096);
            set_s16(77, 4096);
            set_s16(71, -4096);
            set_s16(79, 4096);
            set_s16(73, -4096);
            set_s16(81, -4096);
            set_s16(75, 4096);
            set_s16(83, -4096);
        end
    endtask

    task automatic send_byte(input logic [7:0] value);
        begin
            @(posedge clk);
            rx_data = value;
            rx_valid = 1'b1;
            @(posedge clk);
            rx_valid = 1'b0;
            rx_data = '0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic send_run_frame(input logic [7:0] command, input bit corrupt_checksum);
        logic [7:0] checksum;
        begin
            checksum = command + RUN_VECTOR_PAYLOAD_LEN[7:0] + RUN_VECTOR_PAYLOAD_LEN[15:8];
            for (int i = 0; i < RUN_VECTOR_PAYLOAD_BYTES; i++) begin
                checksum = checksum + payload[i];
            end
            if (corrupt_checksum) begin
                checksum = checksum + 8'h01;
            end

            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(command);
            send_byte(RUN_VECTOR_PAYLOAD_LEN[7:0]);
            send_byte(RUN_VECTOR_PAYLOAD_LEN[15:8]);
            for (int i = 0; i < RUN_VECTOR_PAYLOAD_BYTES; i++) begin
                send_byte(payload[i]);
            end
            send_byte(checksum);
        end
    endtask

    task automatic wait_for_response(input int expected_count, input string test_name);
        int timeout;
        begin
            timeout = 0;
            while ((response_count < expected_count) && (timeout < 20000)) begin
                @(posedge clk);
                timeout++;
            end

            if (response_count < expected_count) begin
                $error("%s timeout waiting for response: got %0d expected %0d",
                       test_name, response_count, expected_count);
                errors++;
            end

            repeat (10) @(posedge clk);
        end
    endtask

    task automatic send_bad_length_frame;
        logic [7:0] checksum;
        begin
            checksum = 8'h01 + BAD_PAYLOAD_LEN[7:0] + BAD_PAYLOAD_LEN[15:8];
            for (int i = 0; i < BAD_PAYLOAD_LEN; i++) begin
                checksum = checksum + payload[i];
            end

            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01);
            send_byte(BAD_PAYLOAD_LEN[7:0]);
            send_byte(BAD_PAYLOAD_LEN[15:8]);
            for (int i = 0; i < BAD_PAYLOAD_LEN; i++) begin
                send_byte(payload[i]);
            end
            send_byte(checksum);
        end
    endtask

    function automatic logic [7:0] response_checksum(input int count);
        logic [7:0] sum;
        begin
            sum = 8'h00;
            for (int i = 2; i < count - 1; i++) begin
                sum = sum + response[i];
            end
            response_checksum = sum;
        end
    endfunction

    task automatic check_error_response(
        input string test_name,
        input logic [7:0] expected_status
    );
        begin
            wait_for_response(ERROR_RESPONSE_BYTES, test_name);

            if (response[0] !== 8'h5A || response[1] !== 8'hA5) begin
                $error("%s bad response header: %02x %02x", test_name, response[0], response[1]);
                errors++;
            end
            if (response[2] !== expected_status) begin
                $error("%s bad status: got %02x expected %02x", test_name, response[2], expected_status);
                errors++;
            end
            if ({response[4], response[3]} !== 16'd0) begin
                $error("%s bad error payload length: got %0d", test_name, {response[4], response[3]});
                errors++;
            end
            if (response[5] !== response_checksum(ERROR_RESPONSE_BYTES)) begin
                $error("%s bad checksum: got %02x expected %02x",
                       test_name, response[5], response_checksum(ERROR_RESPONSE_BYTES));
                errors++;
            end
        end
    endtask

    task automatic check_identity_response;
        int payload_len;
        begin
            wait_for_response(OK_RESPONSE_BYTES, "identity");

            payload_len = {response[4], response[3]};

            if (response[0] !== 8'h5A || response[1] !== 8'hA5) begin
                $error("identity bad response header: %02x %02x", response[0], response[1]);
                errors++;
            end
            if (response[2] !== 8'h00) begin
                $error("identity bad status: got %02x expected 00", response[2]);
                errors++;
            end
            if (payload_len != 22) begin
                $error("identity bad payload length: got %0d expected 22", payload_len);
                errors++;
            end
            if (response[27] !== response_checksum(OK_RESPONSE_BYTES)) begin
                $error("identity bad checksum: got %02x expected %02x",
                       response[27], response_checksum(OK_RESPONSE_BYTES));
                errors++;
            end
            if (response[5] !== 8'd0) begin
                $error("identity bad mode: got %0d expected 0", response[5]);
                errors++;
            end
            if (response[6] !== 8'd4) begin
                $error("identity bad num_iters: got %0d expected 4", response[6]);
                errors++;
            end
            if (response[7] !== 8'h00 || response[8] !== 8'h01 ||
                response[9] !== 8'h03 || response[10] !== 8'h02) begin
                $error("identity bad bits: got %02x %02x %02x %02x expected 00 01 03 02",
                       response[7], response[8], response[9], response[10]);
                errors++;
            end
        end
    endtask

    initial begin
        $display("Starting tb_uart_mimo_protocol");

        clk = 1'b0;
        errors = 0;
        tx_busy = 1'b0;
        tx_busy_countdown = 0;
        response_count = 0;

        apply_reset();
        build_identity_payload();

        clear_response();
        send_run_frame(8'h01, 1'b0);
        check_identity_response();

        clear_response();
        send_run_frame(8'h01, 1'b1);
        check_error_response("bad checksum", 8'h01);

        clear_response();
        send_run_frame(8'h7E, 1'b0);
        check_error_response("bad command", 8'h02);

        clear_response();
        send_bad_length_frame();
        check_error_response("bad length", 8'h03);

        if (errors == 0) begin
            $display("tb_uart_mimo_protocol PASSED");
        end else begin
            $error("tb_uart_mimo_protocol FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule
