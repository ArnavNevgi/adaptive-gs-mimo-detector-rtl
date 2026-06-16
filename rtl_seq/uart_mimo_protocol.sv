`include "fixed_point_pkg.sv"

module uart_mimo_protocol #(
    parameter int NR = fixed_point_pkg::NR,
    parameter int NT = fixed_point_pkg::NT
) (
    input  logic clk,
    input  logic rst_n,

    input  logic rx_valid,
    input  logic [7:0] rx_data,

    output logic tx_start,
    output logic [7:0] tx_data,
    input  logic tx_busy,

    output logic detector_start,
    output logic [1:0] snr_level,
    output logic signed [fixed_point_pkg::GBW_W-1:0] noise_var,
    output logic signed [fixed_point_pkg::H_W-1:0] H_re [NR][NT],
    output logic signed [fixed_point_pkg::H_W-1:0] H_im [NR][NT],
    output logic signed [fixed_point_pkg::Y_W-1:0] y_re [NR],
    output logic signed [fixed_point_pkg::Y_W-1:0] y_im [NR],

    input  logic detector_done,
    input  logic detector_busy,
    input  fixed_point_pkg::gs_mode_t detector_mode,
    input  logic [4:0] detector_num_iters,
    input  logic [1:0] detector_bits [NT],
    input  logic signed [fixed_point_pkg::XOUT_W-1:0] detector_xout_re [NT],
    input  logic signed [fixed_point_pkg::XOUT_W-1:0] detector_xout_im [NT],

    output logic rx_activity,
    output logic done_latched,
    output logic [2:0] last_status,
    output logic [1:0] last_mode
);

    import fixed_point_pkg::*;

    localparam logic [7:0] REQ_HEADER0 = 8'hA5;
    localparam logic [7:0] REQ_HEADER1 = 8'h5A;
    localparam logic [7:0] RSP_HEADER0 = 8'h5A;
    localparam logic [7:0] RSP_HEADER1 = 8'hA5;

    localparam logic [7:0] CMD_RUN_VECTOR = 8'h01;

    localparam logic [7:0] STATUS_OK       = 8'h00;
    localparam logic [7:0] STATUS_CHECKSUM = 8'h01;
    localparam logic [7:0] STATUS_BAD_CMD  = 8'h02;
    localparam logic [7:0] STATUS_BAD_LEN  = 8'h03;
    localparam logic [7:0] STATUS_BUSY     = 8'h04;

    localparam int RUN_VECTOR_PAYLOAD_BYTES = 85;
    localparam int OK_PAYLOAD_BYTES = 22;
    localparam int MAX_PAYLOAD_BYTES = RUN_VECTOR_PAYLOAD_BYTES;
    localparam int MAX_RESPONSE_FRAME_BYTES = 2 + 1 + 2 + OK_PAYLOAD_BYTES + 1;
    localparam logic [15:0] RUN_VECTOR_PAYLOAD_LEN = 16'd85;
    localparam logic [15:0] OK_PAYLOAD_LEN = 16'd22;

    typedef enum logic [4:0] {
        S_RX_HEADER0,
        S_RX_HEADER1,
        S_RX_CMD,
        S_RX_LEN0,
        S_RX_LEN1,
        S_RX_PAYLOAD,
        S_RX_CHECKSUM,
        S_WAIT_DONE,
        S_BUSY_RX_HEADER1,
        S_BUSY_RX_CMD,
        S_BUSY_RX_LEN0,
        S_BUSY_RX_LEN1,
        S_BUSY_RX_PAYLOAD,
        S_BUSY_RX_CHECKSUM,
        S_BUILD_RESPONSE,
        S_TX_START,
        S_TX_WAIT_BUSY,
        S_TX_WAIT_DONE
    } state_t;

    state_t state;

    logic [7:0] rx_cmd;
    logic [15:0] rx_len;
    logic [15:0] rx_index;
    logic [7:0] checksum_acc;

    logic [7:0] payload [0:MAX_PAYLOAD_BYTES-1];
    logic [7:0] response_payload [0:OK_PAYLOAD_BYTES-1];
    logic [7:0] response_frame [0:MAX_RESPONSE_FRAME_BYTES-1];

    logic [7:0] response_status;
    logic [15:0] response_len;
    logic [7:0] response_checksum;
    logic [7:0] response_checksum_comb;
    logic [5:0] response_frame_len;
    logic [5:0] tx_index;
    logic tx_return_to_wait;
    logic ok_response_pending;

    function automatic logic signed [15:0] payload_s16(input int offset);
        begin
            payload_s16 = {payload[offset + 1], payload[offset]};
        end
    endfunction

    always_comb begin
        response_checksum_comb = response_status + response_len[7:0] + response_len[15:8];

        for (int i = 0; i < OK_PAYLOAD_BYTES; i++) begin
            if (i < response_len) begin
                response_checksum_comb = response_checksum_comb + response_payload[i];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_RX_HEADER0;
            rx_cmd <= '0;
            rx_len <= '0;
            rx_index <= '0;
            checksum_acc <= '0;

            tx_start <= 1'b0;
            tx_data <= 8'hFF;
            detector_start <= 1'b0;
            snr_level <= '0;
            noise_var <= '0;
            rx_activity <= 1'b0;
            done_latched <= 1'b0;
            last_status <= STATUS_OK[2:0];
            last_mode <= MODE_GS4;

            response_status <= STATUS_OK;
            response_len <= '0;
            response_checksum <= '0;
            response_frame_len <= '0;
            tx_index <= '0;
            tx_return_to_wait <= 1'b0;
            ok_response_pending <= 1'b0;

            for (int r = 0; r < NR; r++) begin
                y_re[r] <= '0;
                y_im[r] <= '0;

                for (int c = 0; c < NT; c++) begin
                    H_re[r][c] <= '0;
                    H_im[r][c] <= '0;
                end
            end

            for (int i = 0; i < MAX_PAYLOAD_BYTES; i++) begin
                payload[i] <= '0;
            end

            for (int i = 0; i < OK_PAYLOAD_BYTES; i++) begin
                response_payload[i] <= '0;
            end

            for (int i = 0; i < MAX_RESPONSE_FRAME_BYTES; i++) begin
                response_frame[i] <= '0;
            end
        end else begin
            tx_start <= 1'b0;
            detector_start <= 1'b0;
            rx_activity <= 1'b0;

            if (detector_done) begin
                ok_response_pending <= 1'b1;
                done_latched <= 1'b1;
                last_mode <= detector_mode;

                response_payload[0] <= {6'd0, detector_mode};
                response_payload[1] <= {3'd0, detector_num_iters};

                for (int i = 0; i < NT; i++) begin
                    response_payload[2 + i] <= {6'd0, detector_bits[i]};
                    response_payload[6 + 2*i] <= detector_xout_re[i][7:0];
                    response_payload[7 + 2*i] <= detector_xout_re[i][15:8];
                    response_payload[14 + 2*i] <= detector_xout_im[i][7:0];
                    response_payload[15 + 2*i] <= detector_xout_im[i][15:8];
                end
            end

            case (state)
                S_RX_HEADER0: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        checksum_acc <= '0;

                        if (rx_data == REQ_HEADER0) begin
                            state <= S_RX_HEADER1;
                        end
                    end
                end

                S_RX_HEADER1: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;

                        if (rx_data == REQ_HEADER1) begin
                            state <= S_RX_CMD;
                        end else if (rx_data == REQ_HEADER0) begin
                            state <= S_RX_HEADER1;
                        end else begin
                            state <= S_RX_HEADER0;
                        end
                    end
                end

                S_RX_CMD: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        rx_cmd <= rx_data;
                        checksum_acc <= rx_data;
                        state <= S_RX_LEN0;
                    end
                end

                S_RX_LEN0: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        rx_len[7:0] <= rx_data;
                        checksum_acc <= checksum_acc + rx_data;
                        state <= S_RX_LEN1;
                    end
                end

                S_RX_LEN1: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        rx_len[15:8] <= rx_data;
                        checksum_acc <= checksum_acc + rx_data;
                        rx_index <= '0;

                        if ({rx_data, rx_len[7:0]} == 16'd0) begin
                            state <= S_RX_CHECKSUM;
                        end else if ({rx_data, rx_len[7:0]} > MAX_PAYLOAD_BYTES) begin
                            response_status <= STATUS_BAD_LEN;
                            response_len <= 16'd0;
                            last_status <= STATUS_BAD_LEN[2:0];
                            state <= S_BUILD_RESPONSE;
                        end else begin
                            state <= S_RX_PAYLOAD;
                        end
                    end
                end

                S_RX_PAYLOAD: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        payload[rx_index] <= rx_data;
                        checksum_acc <= checksum_acc + rx_data;

                        if (rx_index == rx_len - 1'b1) begin
                            state <= S_RX_CHECKSUM;
                        end else begin
                            rx_index <= rx_index + 1'b1;
                        end
                    end
                end

                S_RX_CHECKSUM: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;

                        if (checksum_acc != rx_data) begin
                            response_status <= STATUS_CHECKSUM;
                            response_len <= 16'd0;
                            last_status <= STATUS_CHECKSUM[2:0];
                            state <= S_BUILD_RESPONSE;
                        end else if (rx_cmd != CMD_RUN_VECTOR) begin
                            response_status <= STATUS_BAD_CMD;
                            response_len <= 16'd0;
                            last_status <= STATUS_BAD_CMD[2:0];
                            state <= S_BUILD_RESPONSE;
                        end else if (rx_len != RUN_VECTOR_PAYLOAD_LEN) begin
                            response_status <= STATUS_BAD_LEN;
                            response_len <= 16'd0;
                            last_status <= STATUS_BAD_LEN[2:0];
                            state <= S_BUILD_RESPONSE;
                        end else if (detector_busy) begin
                            response_status <= STATUS_BUSY;
                            response_len <= 16'd0;
                            last_status <= STATUS_BUSY[2:0];
                            state <= S_BUILD_RESPONSE;
                        end else begin
                            snr_level <= payload[0][1:0];
                            noise_var <= {payload[3][3:0], payload[2], payload[1]};

                            for (int r = 0; r < NR; r++) begin
                                y_re[r] <= payload_s16(69 + 2*r);
                                y_im[r] <= payload_s16(77 + 2*r);

                                for (int c = 0; c < NT; c++) begin
                                    H_re[r][c] <= payload_s16(5 + 2*(r*NT + c));
                                    H_im[r][c] <= payload_s16(37 + 2*(r*NT + c));
                                end
                            end

                            done_latched <= 1'b0;
                            detector_start <= 1'b1;
                            ok_response_pending <= 1'b0;
                            state <= S_WAIT_DONE;
                        end
                    end
                end

                S_WAIT_DONE: begin
                    if (ok_response_pending || detector_done) begin
                        response_status <= STATUS_OK;
                        response_len <= OK_PAYLOAD_LEN;
                        last_status <= STATUS_OK[2:0];
                        tx_return_to_wait <= 1'b0;
                        ok_response_pending <= 1'b0;
                        state <= S_BUILD_RESPONSE;
                    end else if (rx_valid) begin
                        rx_activity <= 1'b1;
                        checksum_acc <= '0;

                        if (rx_data == REQ_HEADER0) begin
                            state <= S_BUSY_RX_HEADER1;
                        end
                    end
                end

                S_BUSY_RX_HEADER1: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;

                        if (rx_data == REQ_HEADER1) begin
                            state <= S_BUSY_RX_CMD;
                        end else if (rx_data == REQ_HEADER0) begin
                            state <= S_BUSY_RX_HEADER1;
                        end else begin
                            state <= S_WAIT_DONE;
                        end
                    end
                end

                S_BUSY_RX_CMD: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        rx_cmd <= rx_data;
                        checksum_acc <= rx_data;
                        state <= S_BUSY_RX_LEN0;
                    end
                end

                S_BUSY_RX_LEN0: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        rx_len[7:0] <= rx_data;
                        checksum_acc <= checksum_acc + rx_data;
                        state <= S_BUSY_RX_LEN1;
                    end
                end

                S_BUSY_RX_LEN1: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        rx_len[15:8] <= rx_data;
                        checksum_acc <= checksum_acc + rx_data;
                        rx_index <= '0;

                        if ({rx_data, rx_len[7:0]} == 16'd0) begin
                            state <= S_BUSY_RX_CHECKSUM;
                        end else if ({rx_data, rx_len[7:0]} > MAX_PAYLOAD_BYTES) begin
                            response_status <= STATUS_BAD_LEN;
                            response_len <= 16'd0;
                            last_status <= STATUS_BAD_LEN[2:0];
                            tx_return_to_wait <= 1'b1;
                            state <= S_BUILD_RESPONSE;
                        end else begin
                            state <= S_BUSY_RX_PAYLOAD;
                        end
                    end
                end

                S_BUSY_RX_PAYLOAD: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        payload[rx_index] <= rx_data;
                        checksum_acc <= checksum_acc + rx_data;

                        if (rx_index == rx_len - 1'b1) begin
                            state <= S_BUSY_RX_CHECKSUM;
                        end else begin
                            rx_index <= rx_index + 1'b1;
                        end
                    end
                end

                S_BUSY_RX_CHECKSUM: begin
                    if (rx_valid) begin
                        rx_activity <= 1'b1;
                        response_len <= 16'd0;
                        tx_return_to_wait <= 1'b1;

                        if (checksum_acc != rx_data) begin
                            response_status <= STATUS_CHECKSUM;
                            last_status <= STATUS_CHECKSUM[2:0];
                        end else if (rx_cmd != CMD_RUN_VECTOR) begin
                            response_status <= STATUS_BAD_CMD;
                            last_status <= STATUS_BAD_CMD[2:0];
                        end else if (rx_len != RUN_VECTOR_PAYLOAD_LEN) begin
                            response_status <= STATUS_BAD_LEN;
                            last_status <= STATUS_BAD_LEN[2:0];
                        end else begin
                            response_status <= STATUS_BUSY;
                            last_status <= STATUS_BUSY[2:0];
                        end

                        state <= S_BUILD_RESPONSE;
                    end
                end

                S_BUILD_RESPONSE: begin
                    response_checksum <= response_checksum_comb;
                    response_frame[0] <= RSP_HEADER0;
                    response_frame[1] <= RSP_HEADER1;
                    response_frame[2] <= response_status;
                    response_frame[3] <= response_len[7:0];
                    response_frame[4] <= response_len[15:8];

                    for (int i = 0; i < OK_PAYLOAD_BYTES; i++) begin
                        if (i < response_len) begin
                            response_frame[5 + i] <= response_payload[i];
                        end
                    end

                    response_frame[5 + response_len[5:0]] <= response_checksum_comb;
                    response_frame_len <= 6 + response_len[5:0];
                    tx_index <= '0;
                    state <= S_TX_START;
                end

                S_TX_START: begin
                    if (!tx_busy) begin
                        tx_data <= response_frame[tx_index];
                        tx_start <= 1'b1;
                        state <= S_TX_WAIT_BUSY;
                    end
                end

                S_TX_WAIT_BUSY: begin
                    if (tx_busy) begin
                        state <= S_TX_WAIT_DONE;
                    end
                end

                S_TX_WAIT_DONE: begin
                    if (!tx_busy) begin
                        if (tx_index == response_frame_len - 1'b1) begin
                            if (tx_return_to_wait) begin
                                tx_return_to_wait <= 1'b0;

                                if (ok_response_pending) begin
                                    response_status <= STATUS_OK;
                                    response_len <= OK_PAYLOAD_LEN;
                                    last_status <= STATUS_OK[2:0];
                                    ok_response_pending <= 1'b0;
                                    state <= S_BUILD_RESPONSE;
                                end else begin
                                    state <= S_WAIT_DONE;
                                end
                            end else begin
                                state <= S_RX_HEADER0;
                            end
                        end else begin
                            tx_index <= tx_index + 1'b1;
                            state <= S_TX_START;
                        end
                    end
                end

                default: begin
                    state <= S_RX_HEADER0;
                end
            endcase
        end
    end

endmodule
