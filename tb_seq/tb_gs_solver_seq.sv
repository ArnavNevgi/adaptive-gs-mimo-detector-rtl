`timescale 1ns/1ps

`include "fixed_point_pkg.sv"

module tb_gs_solver_seq;

    import fixed_point_pkg::*;

    logic clk;
    logic rst_n;
    logic start;

    logic done_seq;
    logic busy_seq;
    logic done_ref;

    logic [4:0] num_iters;

    logic signed [GBW_W-1:0] W_re [NT][NT];
    logic signed [GBW_W-1:0] W_im [NT][NT];

    logic signed [GBW_W-1:0] b_re [NT];
    logic signed [GBW_W-1:0] b_im [NT];

    logic signed [X_W-1:0] x_seq_re [NT];
    logic signed [X_W-1:0] x_seq_im [NT];

    logic signed [X_W-1:0] x_ref_re [NT];
    logic signed [X_W-1:0] x_ref_im [NT];

    int errors;

    gs_solver_seq dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .num_iters(num_iters),
        .W_re(W_re),
        .W_im(W_im),
        .b_re(b_re),
        .b_im(b_im),
        .done(done_seq),
        .busy(busy_seq),
        .x_re(x_seq_re),
        .x_im(x_seq_im)
    );

    gs_solver u_ref (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .num_iters(num_iters),
        .W_re(W_re),
        .W_im(W_im),
        .b_re(b_re),
        .b_im(b_im),
        .done(done_ref),
        .x_re(x_ref_re),
        .x_im(x_ref_im)
    );

    always #5 clk = ~clk;

    task automatic clear_inputs;
        int i;
        int j;
        begin
            for (i = 0; i < NT; i++) begin
                b_re[i] = '0;
                b_im[i] = '0;

                for (j = 0; j < NT; j++) begin
                    W_re[i][j] = '0;
                    W_im[i][j] = '0;
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

    task automatic pulse_start;
        begin
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
        end
    endtask

    task automatic wait_both_done(input string test_name);
        int timeout;
        bit seen_seq;
        bit seen_ref;
        begin
            timeout  = 0;
            seen_seq = 1'b0;
            seen_ref = 1'b0;

            while (!(seen_seq && seen_ref) && timeout < 3000) begin
                @(posedge clk);

                if (done_seq) seen_seq = 1'b1;
                if (done_ref) seen_ref = 1'b1;

                timeout++;
            end

            if (!(seen_seq && seen_ref)) begin
                $error("%s timeout: seen_seq=%0d seen_ref=%0d", test_name, seen_seq, seen_ref);
                errors++;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task automatic check_exact_outputs(input string test_name);
        int i;
        begin
            for (i = 0; i < NT; i++) begin
                if (x_seq_re[i] !== x_ref_re[i]) begin
                    $error("%s x_re[%0d] mismatch: seq=%0d ref=%0d",
                           test_name, i, x_seq_re[i], x_ref_re[i]);
                    errors++;
                end

                if (x_seq_im[i] !== x_ref_im[i]) begin
                    $error("%s x_im[%0d] mismatch: seq=%0d ref=%0d",
                           test_name, i, x_seq_im[i], x_ref_im[i]);
                    errors++;
                end
            end

            if (errors == 0) begin
                $display("PASS %s", test_name);
            end
        end
    endtask

    task automatic setup_identity_system;
        int i;
        begin
            clear_inputs();

            for (i = 0; i < NT; i++) begin
                W_re[i][i] = 20'sd4096;
                W_im[i][i] = 20'sd0;
            end

            b_re[0] = 20'sd4096;   b_im[0] = 20'sd0;
            b_re[1] = 20'sd2048;   b_im[1] = 20'sd2048;
            b_re[2] = -20'sd4096;  b_im[2] = 20'sd0;
            b_re[3] = 20'sd0;      b_im[3] = -20'sd4096;
        end
    endtask

    task automatic setup_nondiagonal_real_system;
        begin
            clear_inputs();

            W_re[0][0] = 20'sd8192;
            W_re[0][1] = 20'sd2048;

            W_re[1][0] = 20'sd2048;
            W_re[1][1] = 20'sd8192;

            W_re[2][2] = 20'sd8192;
            W_re[2][3] = 20'sd1024;

            W_re[3][2] = 20'sd1024;
            W_re[3][3] = 20'sd8192;

            b_re[0] = 20'sd9216;    b_im[0] = 20'sd0;
            b_re[1] = 20'sd6144;    b_im[1] = 20'sd0;
            b_re[2] = -20'sd7936;   b_im[2] = 20'sd0;
            b_re[3] = 20'sd1024;    b_im[3] = 20'sd0;
        end
    endtask

    task automatic setup_complex_coupled_system;
        begin
            clear_inputs();

            W_re[0][0] = 20'sd8192;  W_im[0][0] = 20'sd0;
            W_re[1][1] = 20'sd8192;  W_im[1][1] = 20'sd0;
            W_re[2][2] = 20'sd8192;  W_im[2][2] = 20'sd0;
            W_re[3][3] = 20'sd8192;  W_im[3][3] = 20'sd0;

            W_re[0][1] = 20'sd512;   W_im[0][1] = -20'sd256;
            W_re[1][0] = 20'sd512;   W_im[1][0] = 20'sd256;

            W_re[2][3] = -20'sd384;  W_im[2][3] = 20'sd128;
            W_re[3][2] = -20'sd384;  W_im[3][2] = -20'sd128;

            b_re[0] = 20'sd4096;    b_im[0] = 20'sd2048;
            b_re[1] = -20'sd2048;   b_im[1] = 20'sd1024;
            b_re[2] = 20'sd1024;    b_im[2] = -20'sd4096;
            b_re[3] = -20'sd1024;   b_im[3] = -20'sd2048;
        end
    endtask

    task automatic run_compare_identity(input logic [4:0] iters);
        string name;
        begin
            name = $sformatf("identity_iters_%0d", iters);
            apply_reset();
            setup_identity_system();
            num_iters = iters;
            pulse_start();
            wait_both_done(name);
            check_exact_outputs(name);
        end
    endtask

    task automatic run_compare_nondiagonal(input logic [4:0] iters);
        string name;
        begin
            name = $sformatf("nondiagonal_iters_%0d", iters);
            apply_reset();
            setup_nondiagonal_real_system();
            num_iters = iters;
            pulse_start();
            wait_both_done(name);
            check_exact_outputs(name);
        end
    endtask

    task automatic run_compare_complex(input logic [4:0] iters);
        string name;
        begin
            name = $sformatf("complex_coupled_iters_%0d", iters);
            apply_reset();
            setup_complex_coupled_system();
            num_iters = iters;
            pulse_start();
            wait_both_done(name);
            check_exact_outputs(name);
        end
    endtask

    initial begin
        $display("Starting tb_gs_solver_seq");

        clk       = 1'b0;
        rst_n     = 1'b0;
        start     = 1'b0;
        num_iters = 5'd4;
        errors    = 0;

        apply_reset();

        run_compare_identity(5'd4);
        run_compare_identity(5'd8);
        run_compare_identity(5'd16);

        run_compare_nondiagonal(5'd4);
        run_compare_nondiagonal(5'd8);
        run_compare_nondiagonal(5'd16);

        run_compare_complex(5'd4);
        run_compare_complex(5'd8);
        run_compare_complex(5'd16);

        if (errors == 0) begin
            $display("tb_gs_solver_seq PASSED");
        end else begin
            $error("tb_gs_solver_seq FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule