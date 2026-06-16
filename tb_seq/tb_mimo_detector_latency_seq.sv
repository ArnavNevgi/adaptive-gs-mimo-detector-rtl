`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_mimo_detector_latency_seq;

    import fixed_point_pkg::*;
    import phase6_vectors_pkg::*;

    localparam int NUM_LATENCY_VECTORS = 6;
    localparam int TIMEOUT_CYCLES = 20000;
    localparam real DETECTOR_CLK_HZ = 50_000_000.0;

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
    int csv_fd;
    int report_fd;
    int cycles_by_vector [NUM_LATENCY_VECTORS];
    int mode_by_vector [NUM_LATENCY_VECTORS];
    int iters_by_vector [NUM_LATENCY_VECTORS];
    int pass_by_vector [NUM_LATENCY_VECTORS];
    int mode_count [3];
    int mode_cycles_sum [3];
    int total_cycles;
    int min_cycles;
    int max_cycles;

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

    always #10 clk = ~clk; // 50 MHz detector clock model.

    function automatic int selected_pkg_index(input int sel);
        case (sel)
            0: selected_pkg_index = 0; // identity_noise0_high_snr
            1: selected_pkg_index = 2; // real_nondiagonal_coupled_noise0_high_snr
            2: selected_pkg_index = 3; // random_rayleigh_4db_0
            3: selected_pkg_index = 4; // random_rayleigh_8db_0
            4: selected_pkg_index = 5; // random_rayleigh_12db_0
            5: selected_pkg_index = 6; // weak_dominance_correlated_12db
            default: selected_pkg_index = 0;
        endcase
    endfunction

    function automatic string selected_vector_name(input int sel);
        case (sel)
            0: selected_vector_name = "identity_gs4";
            1: selected_vector_name = "phase6_real_nondiagonal_gs4";
            2: selected_vector_name = "phase6_complex_noise_gs8";
            3: selected_vector_name = "phase6_random_rayleigh_8db_gs8";
            4: selected_vector_name = "phase6_complex_noise_gs16";
            5: selected_vector_name = "phase6_weak_dominance_gs16";
            default: selected_vector_name = "unknown";
        endcase
    endfunction

    function automatic string result_string(input bit passed);
        if (passed) begin
            result_string = "PASS";
        end else begin
            result_string = "FAIL";
        end
    endfunction

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

    task automatic load_vector(input int pkg_idx);
        int r;
        int c;
        begin
            snr_level = V_SNR_LEVEL[pkg_idx];
            noise_var = V_NOISE_VAR[pkg_idx];

            for (r = 0; r < NR; r++) begin
                y_re[r] = V_Y_RE[pkg_idx][r];
                y_im[r] = V_Y_IM[pkg_idx][r];

                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = V_H_RE[pkg_idx][r][c];
                    H_im[r][c] = V_H_IM[pkg_idx][r][c];
                end
            end
        end
    endtask

    task automatic check_outputs(
        input int pkg_idx,
        output bit bits_match,
        output bit xout_match,
        output bit mode_match,
        output bit iters_match
    );
        int i;
        begin
            bits_match = 1'b1;
            xout_match = 1'b1;
            mode_match = (mode_bits === V_EXP_MODE[pkg_idx]);
            iters_match = (num_iters === V_EXP_NUM_ITERS[pkg_idx]);

            for (i = 0; i < NT; i++) begin
                if (bits[i] !== V_EXP_BITS[pkg_idx][i]) begin
                    bits_match = 1'b0;
                end

                if (xout_re[i] !== V_EXP_XOUT_RE[pkg_idx][i] ||
                    xout_im[i] !== V_EXP_XOUT_IM[pkg_idx][i]) begin
                    xout_match = 1'b0;
                end
            end
        end
    endtask

    task automatic run_latency_vector(input int sel);
        int pkg_idx;
        int cycles;
        bit timeout;
        bit bits_match;
        bit xout_match;
        bit mode_match;
        bit iters_match;
        bit passed;
        real vectors_per_second;
        real bits_per_second;
        string name;
        begin
            pkg_idx = selected_pkg_index(sel);
            name = selected_vector_name(sel);
            cycles = 0;
            timeout = 1'b0;

            apply_reset();
            load_vector(pkg_idx);

            @(negedge clk);
            start = 1'b1;
            @(posedge clk); // Start is accepted by the detector on this edge.
            @(negedge clk);
            start = 1'b0;

            while (!done && !timeout) begin
                @(posedge clk);
                cycles++;
                if (cycles > TIMEOUT_CYCLES) begin
                    timeout = 1'b1;
                end
            end

            check_outputs(pkg_idx, bits_match, xout_match, mode_match, iters_match);
            passed = !timeout && bits_match && xout_match && mode_match && iters_match;

            cycles_by_vector[sel] = cycles;
            mode_by_vector[sel] = mode_bits;
            iters_by_vector[sel] = num_iters;
            pass_by_vector[sel] = passed;

            total_cycles += cycles;
            if (sel == 0 || cycles < min_cycles) begin
                min_cycles = cycles;
            end
            if (sel == 0 || cycles > max_cycles) begin
                max_cycles = cycles;
            end

            if (mode_bits <= 2) begin
                mode_count[mode_bits]++;
                mode_cycles_sum[mode_bits] += cycles;
            end

            vectors_per_second = DETECTOR_CLK_HZ / cycles;
            bits_per_second = vectors_per_second * 8.0;

            $display("%-34s mode=%0d exp_mode=%0d iters=%0d exp_iters=%0d cycles=%0d bits=%b %b %b %b xout_re=(%0d,%0d,%0d,%0d) xout_im=(%0d,%0d,%0d,%0d) result=%s",
                     name, mode_bits, V_EXP_MODE[pkg_idx], num_iters, V_EXP_NUM_ITERS[pkg_idx], cycles,
                     bits[0], bits[1], bits[2], bits[3],
                     xout_re[0], xout_re[1], xout_re[2], xout_re[3],
                     xout_im[0], xout_im[1], xout_im[2], xout_im[3],
                     result_string(passed));

            $fwrite(csv_fd, "%s,%0d,%0d,%0d,%0d,%0d,%s\n",
                    name, mode_bits, num_iters, cycles, bits_match, xout_match,
                    result_string(passed));

            $fwrite(report_fd, "%-34s %4d %9d %20d %11s %11s %8s %14.2f %16.2f\n",
                    name, mode_bits, num_iters, cycles,
                    result_string(bits_match), result_string(xout_match),
                    result_string(passed), vectors_per_second, bits_per_second);

            if (!passed) begin
                errors++;
                if (timeout) begin
                    $error("%s timeout before done", name);
                end
                if (!mode_match) begin
                    $error("%s mode mismatch: got %0d expected %0d", name, mode_bits, V_EXP_MODE[pkg_idx]);
                end
                if (!iters_match) begin
                    $error("%s num_iters mismatch: got %0d expected %0d", name, num_iters, V_EXP_NUM_ITERS[pkg_idx]);
                end
                if (!bits_match) begin
                    $error("%s bits mismatch", name);
                end
                if (!xout_match) begin
                    $error("%s xout mismatch", name);
                end
            end

            repeat (3) @(posedge clk);
        end
    endtask

    task automatic write_summary;
        int mode_idx;
        real avg_cycles;
        real mode_avg_cycles;
        real vectors_per_second;
        real bits_per_second;
        begin
            avg_cycles = total_cycles * 1.0 / NUM_LATENCY_VECTORS;

            $display("Latency summary: min=%0d max=%0d avg=%.2f cycles", min_cycles, max_cycles, avg_cycles);
            $display("Mode throughput estimates at 50 MHz:");

            $fwrite(report_fd, "\nSummary statistics\n");
            $fwrite(report_fd, "min_cycles,%0d\n", min_cycles);
            $fwrite(report_fd, "max_cycles,%0d\n", max_cycles);
            $fwrite(report_fd, "average_cycles,%.2f\n", avg_cycles);
            $fwrite(report_fd, "\nThroughput estimates at 50 MHz\n");
            $fwrite(report_fd, "%-8s %14s %18s %22s\n", "mode", "avg_cycles", "vectors_per_second", "detected_bits_per_second");

            for (mode_idx = 0; mode_idx < 3; mode_idx++) begin
                if (mode_count[mode_idx] > 0) begin
                    mode_avg_cycles = mode_cycles_sum[mode_idx] * 1.0 / mode_count[mode_idx];
                    vectors_per_second = DETECTOR_CLK_HZ / mode_avg_cycles;
                    bits_per_second = vectors_per_second * 8.0;
                    $display("  mode %0d: avg_cycles=%.2f vectors/s=%.2f detected_bits/s=%.2f",
                             mode_idx, mode_avg_cycles, vectors_per_second, bits_per_second);
                    $fwrite(report_fd, "%-8d %14.2f %18.2f %22.2f\n",
                            mode_idx, mode_avg_cycles, vectors_per_second, bits_per_second);
                end
            end
        end
    endtask

    initial begin
        $display("Starting tb_mimo_detector_latency_seq");
        $display("Detector clock model: 50 MHz");
        $display("Measuring detector start-accepted edge to done assertion");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        errors = 0;
        total_cycles = 0;
        min_cycles = 0;
        max_cycles = 0;

        for (int i = 0; i < 3; i++) begin
            mode_count[i] = 0;
            mode_cycles_sum[i] = 0;
        end

        csv_fd = $fopen("results/latency_seq/latency_seq_summary.csv", "w");
        report_fd = $fopen("results/latency_seq/latency_seq_report.txt", "w");

        if (csv_fd == 0 || report_fd == 0) begin
            $error("Could not open latency output files under results/latency_seq");
            $finish;
        end

        $fwrite(csv_fd, "vector_name,mode,num_iters,cycles_start_to_done,bits_match,xout_match,result\n");
        $fwrite(report_fd, "Sequential detector latency report\n");
        $fwrite(report_fd, "Clock frequency assumption: 50 MHz\n");
        $fwrite(report_fd, "Latency definition: detector start accepted to done assertion\n\n");
        $fwrite(report_fd, "%-34s %4s %9s %20s %11s %11s %8s %14s %16s\n",
                "vector_name", "mode", "num_iters", "cycles_start_to_done",
                "bits_match", "xout_match", "result", "vectors/s", "detected_bits/s");

        $display("LATENCY_TABLE_START");
        $display("%-34s %4s %9s %20s %8s", "vector_name", "mode", "num_iters", "cycles_start_to_done", "result");

        for (int sel = 0; sel < NUM_LATENCY_VECTORS; sel++) begin
            run_latency_vector(sel);
        end

        write_summary();

        $fclose(csv_fd);
        $fclose(report_fd);

        if (errors == 0) begin
            $display("tb_mimo_detector_latency_seq PASSED");
        end else begin
            $error("tb_mimo_detector_latency_seq FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule
