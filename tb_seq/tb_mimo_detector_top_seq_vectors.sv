`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_mimo_detector_top_seq_vectors;

    import fixed_point_pkg::*;
    import phase6_vectors_pkg::*;

    logic clk;
    logic rst_n;
    logic start;
    logic done;
    logic busy;

    logic [1:0] snr_level;
    logic signed [GBW_W-1:0] noise_var;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];

    logic signed [Y_W-1:0] y_re [NR];
    logic signed [Y_W-1:0] y_im [NR];

    gs_mode_t mode;
    logic [4:0] num_iters;

    logic [1:0] bits [NT];

    logic signed [XOUT_W-1:0] xout_re [NT];
    logic signed [XOUT_W-1:0] xout_im [NT];

    logic [1:0] mode_bits;

    int errors;
    int warnings;
    int vec;
    int mode0_count;
    int mode1_count;
    int mode2_count;

    assign mode_bits = mode;

    mimo_detector_top_seq dut (
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
        .mode(mode),
        .num_iters(num_iters),
        .bits(bits),
        .xout_re(xout_re),
        .xout_im(xout_im)
    );

    always #5 clk = ~clk;

    task automatic clear_inputs;
        int r;
        int c;
        begin
            snr_level = 2'd0;
            noise_var = '0;

            for (r = 0; r < NR; r++) begin
                y_re[r] = '0;
                y_im[r] = '0;

                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = '0;
                    H_im[r][c] = '0;
                end
            end
        end
    endtask

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            start = 1'b0;
            clear_inputs();

            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic load_vector(input int v);
        int r;
        int c;
        begin
            snr_level = V_SNR_LEVEL[v];
            noise_var = V_NOISE_VAR[v];

            for (r = 0; r < NR; r++) begin
                y_re[r] = V_Y_RE[v][r];
                y_im[r] = V_Y_IM[v][r];

                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = V_H_RE[v][r][c];
                    H_im[r][c] = V_H_IM[v][r][c];
                end
            end
        end
    endtask

    task automatic pulse_start;
        begin
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    task automatic wait_done(input int v);
        int timeout;
        begin
            timeout = 0;

            while (!done && timeout < 10000) begin
                @(posedge clk);
                timeout++;
            end

            if (!done) begin
                $error("Vector %0d timeout waiting for done", v);
                errors++;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic check_vector(input int v);
        int i;
        begin
            if (mode_bits !== V_EXP_MODE[v]) begin
                $error("Vector %0d mode mismatch: got %0d expected %0d",
                       v, mode_bits, V_EXP_MODE[v]);
                errors++;
            end

            if (num_iters !== V_EXP_NUM_ITERS[v]) begin
                $error("Vector %0d num_iters mismatch: got %0d expected %0d",
                       v, num_iters, V_EXP_NUM_ITERS[v]);
                errors++;
            end

            for (i = 0; i < NT; i++) begin
                if (xout_re[i] !== V_EXP_XOUT_RE[v][i]) begin
                    $error("Vector %0d xout_re[%0d] mismatch: got %0d expected %0d",
                           v, i, xout_re[i], V_EXP_XOUT_RE[v][i]);
                    errors++;
                end

                if (xout_im[i] !== V_EXP_XOUT_IM[v][i]) begin
                    $error("Vector %0d xout_im[%0d] mismatch: got %0d expected %0d",
                           v, i, xout_im[i], V_EXP_XOUT_IM[v][i]);
                    errors++;
                end

                if (bits[i] !== V_EXP_BITS[v][i]) begin
                    $error("Vector %0d bits[%0d] mismatch: got %b expected %b",
                           v, i, bits[i], V_EXP_BITS[v][i]);
                    errors++;
                end
            end

            case (mode_bits)
                2'd0: mode0_count++;
                2'd1: mode1_count++;
                2'd2: mode2_count++;
                default: begin
                    $error("Vector %0d illegal mode %0d", v, mode_bits);
                    errors++;
                end
            endcase

            if ((errors == 0) && ((v < 10) || (v % 10 == 0))) begin
                $display("PASS vector %0d mode=%0d num_iters=%0d", v, mode_bits, num_iters);
            end
        end
    endtask

    initial begin
        $display("Starting tb_mimo_detector_top_seq_vectors");
        $display("NUM_PHASE6_VECTORS = %0d", NUM_PHASE6_VECTORS);

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;

        errors = 0;
        warnings = 0;
        mode0_count = 0;
        mode1_count = 0;
        mode2_count = 0;

        apply_reset();

        for (vec = 0; vec < NUM_PHASE6_VECTORS; vec++) begin
            load_vector(vec);
            pulse_start();
            wait_done(vec);
            check_vector(vec);

            if (errors != 0) begin
                $error("Stopping after vector %0d due to errors", vec);
                break;
            end

            // Let DUT return to IDLE cleanly before next vector.
            repeat (3) @(posedge clk);
        end

        $display("Mode count GS-4  = %0d", mode0_count);
        $display("Mode count GS-8  = %0d", mode1_count);
        $display("Mode count GS-16 = %0d", mode2_count);

        if (errors == 0) begin
            $display("tb_mimo_detector_top_seq_vectors PASSED");
        end else begin
            $error("tb_mimo_detector_top_seq_vectors FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule