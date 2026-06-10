`timescale 1ns/1ps

module tb_signed_divider_seq;

    localparam int NUM_W = 56;
    localparam int DEN_W = 20;

    logic clk;
    logic rst_n;
    logic start;
    logic done;
    logic busy;

    logic signed [NUM_W-1:0] numerator;
    logic signed [DEN_W-1:0] denominator;
    logic signed [NUM_W-1:0] quotient;

    int errors;
    int case_count;

    signed_divider_seq #(
        .NUM_W(NUM_W),
        .DEN_W(DEN_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .numerator(numerator),
        .denominator(denominator),
        .done(done),
        .busy(busy),
        .quotient(quotient)
    );

    always #5 clk = ~clk;

    function automatic logic signed [NUM_W-1:0] ref_divide(
        input logic signed [NUM_W-1:0] num,
        input logic signed [DEN_W-1:0] den
    );
        begin
            if (den == '0)
                ref_divide = '0;
            else
                ref_divide = num / den;
        end
    endfunction

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            start = 1'b0;
            numerator = '0;
            denominator = '0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_case(
        input logic signed [NUM_W-1:0] num,
        input logic signed [DEN_W-1:0] den
    );
        logic signed [NUM_W-1:0] expected;
        int timeout;
        begin
            case_count++;
            expected = ref_divide(num, den);

            @(posedge clk);
            numerator = num;
            denominator = den;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            timeout = 0;
            while (!done && timeout < NUM_W + 10) begin
                @(posedge clk);
                timeout++;
            end

            if (!done) begin
                $error("case %0d timeout: numerator=%0d denominator=%0d",
                       case_count, num, den);
                errors++;
            end else if (quotient !== expected) begin
                $error("case %0d quotient mismatch: numerator=%0d denominator=%0d got=%0d expected=%0d",
                       case_count, num, den, quotient, expected);
                errors++;
            end

            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        $display("Starting tb_signed_divider_seq");

        clk = 1'b0;
        errors = 0;
        case_count = 0;

        apply_reset();

        run_case(56'sd0, 20'sd5);
        run_case(56'sd123456, 20'sd4096);
        run_case(-56'sd123456, 20'sd4096);
        run_case(56'sd123456, -20'sd4096);
        run_case(-56'sd123456, -20'sd4096);
        run_case(56'sd1099511627776, 20'sd123);
        run_case(-56'sd1099511627776, 20'sd123);
        run_case(56'sd987654321, 20'sd1);
        run_case(56'sd987654321, -20'sd1);
        run_case(56'sd987654321, 20'sd0);

        for (int k = 0; k < 100; k++) begin
            logic signed [NUM_W-1:0] rand_num;
            logic signed [DEN_W-1:0] rand_den;

            rand_num = $signed({$urandom(), $urandom()}) >>> 8;
            rand_den = $signed($urandom());

            if (rand_den == '0)
                rand_den = 20'sd37;

            run_case(rand_num, rand_den);
        end

        if (errors == 0) begin
            $display("tb_signed_divider_seq PASSED (%0d cases)", case_count);
        end else begin
            $error("tb_signed_divider_seq FAILED with %0d errors", errors);
        end

        $finish;
    end

endmodule
