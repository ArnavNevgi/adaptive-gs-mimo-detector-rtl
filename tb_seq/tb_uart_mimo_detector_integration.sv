`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_uart_mimo_detector_integration;

    import fixed_point_pkg::*;

    localparam int RUN_VECTOR_PAYLOAD_BYTES = 85;
    localparam int OK_RESPONSE_BYTES = 28;
    localparam int ERROR_RESPONSE_BYTES = 6;
    localparam int MAX_RESPONSE_BYTES = 96;
    localparam logic [15:0] RUN_VECTOR_PAYLOAD_LEN = 16'd85;

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
    logic [7:0] response [0:MAX_RESPONSE_BYTES-1];

    gs_mode_t done_mode;
    logic [4:0] done_num_iters;
    logic [1:0] done_bits [NT];
    logic signed [XOUT_W-1:0] done_xout_re [NT];
    logic signed [XOUT_W-1:0] done_xout_im [NT];

    int response_count;
    int errors;
    int tx_busy_countdown;
    int detector_start_count;
    logic detector_start_d;
    logic detector_done_seen;
    logic enforce_wait_for_done;

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

            for (int i = 0; i < MAX_RESPONSE_BYTES; i++) begin
                response[i] <= '0;
            end
        end else begin
            if (tx_start) begin
                if (response_count < MAX_RESPONSE_BYTES) begin
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

    function automatic logic signed [H_W-1:0] expected_h_re(input int r, input int c);
        begin
            expected_h_re = (r == c) ? 4096 : 0;
        end
    endfunction

    function automatic logic signed [H_W-1:0] expected_h_im(input int r, input int c);
        begin
            expected_h_im = 0;
        end
    endfunction

    function automatic logic signed [Y_W-1:0] expected_y_re(input int r);
        begin
            case (r)
                0: expected_y_re = 4096;
                1: expected_y_re = -4096;
                2: expected_y_re = -4096;
                default: expected_y_re = 4096;
            endcase
        end
    endfunction

    function automatic logic signed [Y_W-1:0] expected_y_im(input int r);
        begin
            case (r)
                0: expected_y_im = 4096;
                1: expected_y_im = 4096;
                2: expected_y_im = -4096;
                default: expected_y_im = -4096;
            endcase
        end
    endfunction

    task automatic check_detector_inputs;
        begin
            if (snr_level !== 2'd2) begin
                $error("detector input snr_level mismatch: got %0d expected 2", snr_level);
                errors++;
            end

            if (noise_var !== '0) begin
                $error("detector input noise_var mismatch: got 0x%0h expected 0", noise_var);
                errors++;
            end

            for (int r = 0; r < NR; r++) begin
                if (y_re[r] !== expected_y_re(r)) begin
                    $error("detector input y_re[%0d] mismatch: got %0d expected %0d",
                           r, y_re[r], expected_y_re(r));
                    errors++;
                end

                if (y_im[r] !== expected_y_im(r)) begin
                    $error("detector input y_im[%0d] mismatch: got %0d expected %0d",
                           r, y_im[r], expected_y_im(r));
                    errors++;
                end

                for (int c = 0; c < NT; c++) begin
                    if (H_re[r][c] !== expected_h_re(r, c)) begin
                        $error("detector input H_re[%0d][%0d] mismatch: got %0d expected %0d",
                               r, c, H_re[r][c], expected_h_re(r, c));
                        errors++;
                    end

                    if (H_im[r][c] !== expected_h_im(r, c)) begin
                        $error("detector input H_im[%0d][%0d] mismatch: got %0d expected 0",
                               r, c, H_im[r][c]);
                        errors++;
                    end
                end
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            detector_start_count <= 0;
            detector_start_d <= 1'b0;
            detector_done_seen <= 1'b0;
            done_mode <= MODE_GS4;
            done_num_iters <= '0;

            for (int i = 0; i < NT; i++) begin
                done_bits[i] <= '0;
                done_xout_re[i] <= '0;
                done_xout_im[i] <= '0;
            end
        end else begin
            if (detector_start) begin
                detector_start_count <= detector_start_count + 1;
                check_detector_inputs();

                if (detector_start_d) begin
                    $error("detector_start stayed high for more than one clock");
                    errors++;
                end

                if (detector_busy) begin
                    $error("detector_start asserted while detector_busy was active");
                    errors++;
                end
            end

            if (tx_start && enforce_wait_for_done && !detector_done_seen) begin
                $error("protocol transmitted an OK response byte before detector_done");
                errors++;
            end

            if (detector_done) begin
                detector_done_seen <= 1'b1;
                done_mode <= detector_mode;
                done_num_iters <= detector_num_iters;

                for (int i = 0; i < NT; i++) begin
                    done_bits[i] <= detector_bits[i];
                    done_xout_re[i] <= detector_xout_re[i];
                    done_xout_im[i] <= detector_xout_im[i];
                end
            end

            detector_start_d <= detector_start;
        end
    end

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            rx_valid = 1'b0;
            rx_data = '0;
            enforce_wait_for_done = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (5) @(posedge clk);
        end
    endtask

    task automatic clear_response;
        begin
            response_count = 0;
            for (int i = 0; i < MAX_RESPONSE_BYTES; i++) begin
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

    task automatic send_run_frame;
        logic [7:0] checksum;
        begin
            checksum = 8'h01 + RUN_VECTOR_PAYLOAD_LEN[7:0] + RUN_VECTOR_PAYLOAD_LEN[15:8];
            for (int i = 0; i < RUN_VECTOR_PAYLOAD_BYTES; i++) begin
                checksum = checksum + payload[i];
            end

            send_byte(8'hA5);
            send_byte(8'h5A);
            send_byte(8'h01);
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
            while ((response_count < expected_count) && (timeout < 50000)) begin
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

    function automatic logic [7:0] response_checksum(input int offset, input int count);
        logic [7:0] sum;
        begin
            sum = 8'h00;
            for (int i = offset + 2; i < offset + count - 1; i++) begin
                sum = sum + response[i];
            end
            response_checksum = sum;
        end
    endfunction

    task automatic check_identity_response;
        int payload_len;
        begin
            wait_for_response(OK_RESPONSE_BYTES, "identity integration");

            payload_len = {response[4], response[3]};

            if (response[0] !== 8'h5A || response[1] !== 8'hA5) begin
                $error("identity response header mismatch: got %02x %02x", response[0], response[1]);
                errors++;
            end

            if (response[2] !== 8'h00) begin
                $error("identity response status mismatch: got %02x expected 00", response[2]);
                errors++;
            end

            if (payload_len != 22) begin
                $error("identity response payload length mismatch: got %0d expected 22", payload_len);
                errors++;
            end

            if (response[27] !== response_checksum(0, OK_RESPONSE_BYTES)) begin
                $error("identity response checksum mismatch: got %02x expected %02x",
                       response[27], response_checksum(0, OK_RESPONSE_BYTES));
                errors++;
            end

            if (!detector_done_seen) begin
                $error("identity response arrived without detector_done being observed");
                errors++;
            end

            if (detector_start_count != 1) begin
                $error("identity expected one detector_start pulse, saw %0d", detector_start_count);
                errors++;
            end

            if (response[5] !== {6'd0, done_mode}) begin
                $error("identity response mode does not match detector output: got %0d expected %0d",
                       response[5], {6'd0, done_mode});
                errors++;
            end

            if (response[6] !== {3'd0, done_num_iters}) begin
                $error("identity response num_iters does not match detector output: got %0d expected %0d",
                       response[6], {3'd0, done_num_iters});
                errors++;
            end

            for (int i = 0; i < NT; i++) begin
                if (response[7 + i] !== {6'd0, done_bits[i]}) begin
                    $error("identity response bits[%0d] does not match detector output: got %02x expected %02x",
                           i, response[7 + i], {6'd0, done_bits[i]});
                    errors++;
                end

                if (response[11 + 2*i] !== done_xout_re[i][7:0] ||
                    response[12 + 2*i] !== done_xout_re[i][15:8]) begin
                    $error("identity response xout_re[%0d] does not match detector output", i);
                    errors++;
                end

                if (response[19 + 2*i] !== done_xout_im[i][7:0] ||
                    response[20 + 2*i] !== done_xout_im[i][15:8]) begin
                    $error("identity response xout_im[%0d] does not match detector output", i);
                    errors++;
                end
            end

            if (response[5] !== 8'd0) begin
                $error("identity expected mode 0, got %0d", response[5]);
                errors++;
            end

            if (response[6] !== 8'd4) begin
                $error("identity expected num_iters 4, got %0d", response[6]);
                errors++;
            end

            if (response[7] !== 8'h00 || response[8] !== 8'h01 ||
                response[9] !== 8'h03 || response[10] !== 8'h02) begin
                $error("identity expected bits 00 01 03 02, got %02x %02x %02x %02x",
                       response[7], response[8], response[9], response[10]);
                errors++;
            end
        end
    endtask

    function automatic bit response_has_status(input logic [7:0] expected_status);
        begin
            response_has_status = 1'b0;
            for (int i = 0; i <= MAX_RESPONSE_BYTES - ERROR_RESPONSE_BYTES; i++) begin
                if (i + ERROR_RESPONSE_BYTES <= response_count &&
                    response[i] == 8'h5A &&
                    response[i + 1] == 8'hA5 &&
                    response[i + 2] == expected_status &&
                    response[i + 3] == 8'h00 &&
                    response[i + 4] == 8'h00 &&
                    response[i + 5] == response_checksum(i, ERROR_RESPONSE_BYTES)) begin
                    response_has_status = 1'b1;
                end
            end
        end
    endfunction

    task automatic wait_for_status(input logic [7:0] expected_status, input string test_name);
        int timeout;
        begin
            timeout = 0;
            while (!response_has_status(expected_status) && (timeout < 100000)) begin
                @(posedge clk);
                timeout++;
            end

            if (!response_has_status(expected_status)) begin
                $error("%s did not receive expected status 0x%02x while detector was busy; response_count=%0d",
                       test_name, expected_status, response_count);
                errors++;
            end
        end
    endtask

    task automatic wait_until_busy;
        int timeout;
        begin
            timeout = 0;
            while (!detector_busy && (timeout < 50000)) begin
                @(posedge clk);
                timeout++;
            end

            if (!detector_busy) begin
                $error("timeout waiting for real detector_busy");
                errors++;
            end
        end
    endtask

    initial begin
        $display("Starting tb_uart_mimo_detector_integration");

        clk = 1'b0;
        errors = 0;
        build_identity_payload();

        apply_reset();
        clear_response();
        enforce_wait_for_done = 1'b1;
        send_run_frame();
        check_identity_response();
        enforce_wait_for_done = 1'b0;

        apply_reset();
        clear_response();
        send_run_frame();
        wait_until_busy();
        send_run_frame();
        wait_for_status(8'h04, "busy integration");

        if (errors == 0) begin
            $display("tb_uart_mimo_detector_integration PASSED");
        end else begin
            $error("tb_uart_mimo_detector_integration FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule
