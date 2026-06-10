`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_gram_matrix_seq;

    import fixed_point_pkg::*;

    logic clk;
    logic rst_n;
    logic start;
    logic done;
    logic busy;

    logic signed [H_W-1:0] H_re [NR][NT];
    logic signed [H_W-1:0] H_im [NR][NT];

    logic signed [GBW_W-1:0] G_seq_re [NT][NT];
    logic signed [GBW_W-1:0] G_seq_im [NT][NT];

    logic signed [GBW_W-1:0] G_ref_re [NT][NT];
    logic signed [GBW_W-1:0] G_ref_im [NT][NT];

    int errors;

    gram_matrix_seq #(
        .NR(NR),
        .NT(NT)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .H_re(H_re),
        .H_im(H_im),
        .done(done),
        .busy(busy),
        .G_re(G_seq_re),
        .G_im(G_seq_im)
    );

            gram_matrix_compute #(
        .NR(NR),
        .NT(NT)
    ) u_ref (
        .H_re(H_re),
        .H_im(H_im),
        .G_re(G_ref_re),
        .G_im(G_ref_im)
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
            while (!done && timeout < 500) begin
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
                    if (G_seq_re[i][j] !== G_ref_re[i][j]) begin
                        $error("%s G_re[%0d][%0d] mismatch: seq=%0d ref=%0d",
                               test_name, i, j, G_seq_re[i][j], G_ref_re[i][j]);
                        errors++;
                    end

                    if (G_seq_im[i][j] !== G_ref_im[i][j]) begin
                        $error("%s G_im[%0d][%0d] mismatch: seq=%0d ref=%0d",
                               test_name, i, j, G_seq_im[i][j], G_ref_im[i][j]);
                        errors++;
                    end
                end
            end

            if (errors == 0) begin
                $display("PASS %s", test_name);
            end
        end
    endtask

    task automatic set_identity_H;
        int r;
        int c;
        begin
            for (r = 0; r < NR; r++) begin
                for (c = 0; c < NT; c++) begin
                    H_re[r][c] = '0;
                    H_im[r][c] = '0;

                    if (r == c) begin
                        H_re[r][c] = 16'sd4096; // 1.0 in Q4.12
                    end
                end
            end
        end
    endtask

    task automatic set_known_complex_H;
        begin
            // Small fixed complex matrix in Q4.12.
            // Values chosen to avoid overflow and exercise real/imag paths.

            H_re[0][0] = 16'sd4096;  H_im[0][0] = 16'sd0;
            H_re[0][1] = 16'sd2048;  H_im[0][1] = 16'sd1024;
            H_re[0][2] = -16'sd1024; H_im[0][2] = 16'sd2048;
            H_re[0][3] = 16'sd512;   H_im[0][3] = -16'sd1024;

            H_re[1][0] = 16'sd1024;  H_im[1][0] = -16'sd2048;
            H_re[1][1] = 16'sd4096;  H_im[1][1] = 16'sd0;
            H_re[1][2] = 16'sd2048;  H_im[1][2] = 16'sd512;
            H_re[1][3] = -16'sd512;  H_im[1][3] = 16'sd1024;

            H_re[2][0] = -16'sd2048; H_im[2][0] = 16'sd1024;
            H_re[2][1] = 16'sd512;   H_im[2][1] = -16'sd512;
            H_re[2][2] = 16'sd4096;  H_im[2][2] = 16'sd0;
            H_re[2][3] = 16'sd1024;  H_im[2][3] = 16'sd2048;

            H_re[3][0] = 16'sd512;   H_im[3][0] = 16'sd512;
            H_re[3][1] = -16'sd1024; H_im[3][1] = 16'sd2048;
            H_re[3][2] = 16'sd2048;  H_im[3][2] = -16'sd1024;
            H_re[3][3] = 16'sd4096;  H_im[3][3] = 16'sd0;
        end
    endtask

    initial begin
        $display("Starting tb_gram_matrix_seq");

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        errors = 0;

        apply_reset();

        set_identity_H();
        pulse_start();
        wait_done();
        check_outputs("identity_H");

        apply_reset();

        set_known_complex_H();
        pulse_start();
        wait_done();
        check_outputs("known_complex_H");

        if (errors == 0) begin
            $display("tb_gram_matrix_seq PASSED");
        end else begin
            $error("tb_gram_matrix_seq FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule