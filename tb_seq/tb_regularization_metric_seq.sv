`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_regularization_metric_seq;

    import fixed_point_pkg::*;

    logic clk;
    logic rst_n;
    logic start;
    logic done;
    logic busy;

    logic signed [GBW_W-1:0] G_re [NT][NT];
    logic signed [GBW_W-1:0] G_im [NT][NT];
    logic signed [GBW_W-1:0] noise_var;

    logic signed [GBW_W-1:0] W_seq_re [NT][NT];
    logic signed [GBW_W-1:0] W_seq_im [NT][NT];

    logic signed [GBW_W-1:0] W_ref_re [NT][NT];
    logic signed [GBW_W-1:0] W_ref_im [NT][NT];

    logic [31:0] diag_seq;
    logic [31:0] offdiag_seq;

    logic [31:0] diag_ref;
    logic [31:0] offdiag_ref;

    int errors;

    regularization_metric_seq #(
        .NT(NT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .G_re(G_re),
        .G_im(G_im),
        .noise_var(noise_var),
        .done(done),
        .busy(busy),
        .W_re(W_seq_re),
        .W_im(W_seq_im),
        .diag_sum(diag_seq),
        .offdiag_sum(offdiag_seq)
    );

    regularization_unit u_regularization_ref (
        .G_re(G_re),
        .G_im(G_im),
        .noise_var(noise_var),
        .W_re(W_ref_re),
        .W_im(W_ref_im)
    );

    condition_metric_unit u_metric_ref (
        .G_re(G_re),
        .G_im(G_im),
        .diag_sum(diag_ref),
        .offdiag_sum(offdiag_ref)
    );

    always #5 clk = ~clk;

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            start = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
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

    task automatic wait_done;
        int timeout;
        begin
            timeout = 0;

            while (!done && timeout < 200) begin
                @(posedge clk);
                timeout++;
            end

            if (!done) begin
                $error("Timeout waiting for done");
                errors++;
            end

            @(posedge clk);
        end
    endtask

    task automatic check_outputs(input string test_name);
        int i;
        int j;
        begin
            for (i = 0; i < NT; i++) begin
                for (j = 0; j < NT; j++) begin
                    if (W_seq_re[i][j] !== W_ref_re[i][j]) begin
                        $error("%s W_re[%0d][%0d] mismatch: seq=%0d ref=%0d",
                               test_name, i, j, W_seq_re[i][j], W_ref_re[i][j]);
                        errors++;
                    end

                    if (W_seq_im[i][j] !== W_ref_im[i][j]) begin
                        $error("%s W_im[%0d][%0d] mismatch: seq=%0d ref=%0d",
                               test_name, i, j, W_seq_im[i][j], W_ref_im[i][j]);
                        errors++;
                    end
                end
            end

            if (diag_seq !== diag_ref) begin
                $error("%s diag_sum mismatch: seq=%0d ref=%0d",
                       test_name, diag_seq, diag_ref);
                errors++;
            end

            if (offdiag_seq !== offdiag_ref) begin
                $error("%s offdiag_sum mismatch: seq=%0d ref=%0d",
                       test_name, offdiag_seq, offdiag_ref);
                errors++;
            end

            if (errors == 0) begin
                $display("PASS %s", test_name);
            end
        end
    endtask

    task automatic set_simple_G;
        int i;
        int j;
        begin
            for (i = 0; i < NT; i++) begin
                for (j = 0; j < NT; j++) begin
                    G_re[i][j] = '0;
                    G_im[i][j] = '0;
                end
            end

            G_re[0][0] = 20'sd4096;  G_im[0][0] = 20'sd0;
            G_re[1][1] = 20'sd4096;  G_im[1][1] = 20'sd0;
            G_re[2][2] = 20'sd4096;  G_im[2][2] = 20'sd0;
            G_re[3][3] = 20'sd4096;  G_im[3][3] = 20'sd0;

            G_re[0][1] = 20'sd512;   G_im[0][1] = -20'sd256;
            G_re[1][0] = 20'sd512;   G_im[1][0] = 20'sd256;

            G_re[2][3] = -20'sd384;  G_im[2][3] = 20'sd128;
            G_re[3][2] = -20'sd384;  G_im[3][2] = -20'sd128;

            noise_var = 20'sd256;
        end
    endtask

    task automatic set_mixed_G;
        int i;
        int j;
        begin
            for (i = 0; i < NT; i++) begin
                for (j = 0; j < NT; j++) begin
                    G_re[i][j] = 20'sd0;
                    G_im[i][j] = 20'sd0;
                end
            end

            G_re[0][0] = 20'sd8192;   G_im[0][0] = 20'sd0;
            G_re[1][1] = 20'sd6144;   G_im[1][1] = 20'sd0;
            G_re[2][2] = 20'sd5120;   G_im[2][2] = 20'sd0;
            G_re[3][3] = 20'sd7168;   G_im[3][3] = 20'sd0;

            G_re[0][1] = -20'sd1024;  G_im[0][1] = 20'sd512;
            G_re[0][2] = 20'sd768;    G_im[0][2] = -20'sd256;
            G_re[0][3] = -20'sd512;   G_im[0][3] = -20'sd128;

            G_re[1][0] = -20'sd1024;  G_im[1][0] = -20'sd512;
            G_re[1][2] = 20'sd384;    G_im[1][2] = 20'sd256;
            G_re[1][3] = -20'sd640;   G_im[1][3] = 20'sd320;

            G_re[2][0] = 20'sd768;    G_im[2][0] = 20'sd256;
            G_re[2][1] = 20'sd384;    G_im[2][1] = -20'sd256;
            G_re[2][3] = 20'sd896;    G_im[2][3] = -20'sd448;

            G_re[3][0] = -20'sd512;   G_im[3][0] = 20'sd128;
            G_re[3][1] = -20'sd640;   G_im[3][1] = -20'sd320;
            G_re[3][2] = 20'sd896;    G_im[3][2] = 20'sd448;

            noise_var = 20'sd1024;
        end
    endtask

    initial begin
        $display("Starting tb_regularization_metric_seq");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        errors = 0;

        apply_reset();

        set_simple_G();
        pulse_start();
        wait_done();
        check_outputs("simple_G");

        apply_reset();

        set_mixed_G();
        pulse_start();
        wait_done();
        check_outputs("mixed_G");

        if (errors == 0) begin
            $display("tb_regularization_metric_seq PASSED");
        end else begin
            $error("tb_regularization_metric_seq FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule