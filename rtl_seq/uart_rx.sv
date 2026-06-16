`timescale 1ns/1ps

// 8N1 UART receiver.
module uart_rx #(
    parameter int CLKS_PER_BIT = 434
) (
    input  logic clk,
    input  logic rst_n,
    input  logic rx,

    output logic rx_valid,
    output logic [7:0] rx_data
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_START,
        S_DATA,
        S_STOP,
        S_CLEANUP
    } state_t;

    state_t state;

    (* ASYNC_REG = "TRUE" *) logic [1:0] rx_sync;
    logic [15:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] rx_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync <= 2'b11;
        end else begin
            rx_sync <= {rx_sync[0], rx};
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            clk_count <= '0;
            bit_index <= '0;
            rx_shift <= '0;
            rx_data <= '0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;

                    if (rx_sync[1] == 1'b0) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx_sync[1] == 1'b0) begin
                            clk_count <= '0;
                            state <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= '0;
                        rx_shift[bit_index] <= rx_sync[1];

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
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        rx_data <= rx_shift;
                        rx_valid <= rx_sync[1];
                        clk_count <= '0;
                        state <= S_CLEANUP;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                S_CLEANUP: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
