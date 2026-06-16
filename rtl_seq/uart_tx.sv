`timescale 1ns/1ps

// 8N1 UART transmitter.
module uart_tx #(
    parameter int CLKS_PER_BIT = 434
) (
    input  logic clk,
    input  logic rst_n,
    input  logic tx_start,
    input  logic [7:0] tx_data,

    output logic tx_busy,
    output logic tx_done,
    output logic tx
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP,
        S_CLEANUP
    } state_t;

    state_t state;

    logic [15:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] tx_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            clk_count <= '0;
            bit_index <= '0;
            tx_shift <= '0;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
            tx <= 1'b1;
        end else begin
            tx_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_count <= '0;
                    bit_index <= '0;

                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx_busy <= 1'b1;
                        state <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        state <= S_DATA;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_DATA: begin
                    tx <= tx_shift[bit_index];

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;

                        if (bit_index == 3'd7) begin
                            bit_index <= '0;
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        state <= S_CLEANUP;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_CLEANUP: begin
                    tx_busy <= 1'b0;
                    tx_done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
