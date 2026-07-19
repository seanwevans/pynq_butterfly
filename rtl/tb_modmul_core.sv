`timescale 1ns/1ps

module tb_modmul_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;
    logic start   = 1'b0;

    logic [31:0] a = 32'd0;
    logic [31:0] b = 32'd0;
    logic [31:0] q = 32'd0;

    logic [31:0] result;
    logic busy;
    logic done;

    integer test_count = 0;
    integer i;

    modmul_core dut (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (start),
        .a       (a),
        .b       (b),
        .q       (q),
        .result  (result),
        .busy    (busy),
        .done    (done)
    );

    always #5 clk = ~clk;

    task automatic run_case(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [31:0] test_q
    );
        logic [63:0] product;
        logic [31:0] expected;
        integer timeout_cycles;

        begin
            // The hardware core requires its multiplicand to be reduced.
            if ((test_q != 0) && (test_a >= test_q))
            begin
                $display(
                    "INVALID TEST: a=%0d must be less than q=%0d",
                    test_a,
                    test_q
                );
                $fatal(1);
            end

            // Force both operands to 64 bits before multiplication.
            product =
                {32'd0, test_a} *
                {32'd0, test_b};

            if (test_q == 0)
                expected = 32'd0;
            else
                expected = product % test_q;

            @(negedge clk);

            a     = test_a;
            b     = test_b;
            q     = test_q;
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            timeout_cycles = 0;

            while ((done !== 1'b1) && (timeout_cycles < 100))
            begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end

            if (done !== 1'b1)
            begin
                $display(
                    "TIMEOUT a=%0d b=%0d q=%0d busy=%0b",
                    test_a,
                    test_b,
                    test_q,
                    busy
                );
                $fatal(1);
            end

            #1;

            if (result !== expected)
            begin
                $display(
                    "FAIL a=%0d b=%0d q=%0d result=%0d expected=%0d",
                    test_a,
                    test_b,
                    test_q,
                    result,
                    expected
                );
                $fatal(1);
            end

            test_count = test_count + 1;
        end
    endtask

    initial
    begin
        repeat (4) @(posedge clk);
        reset_n = 1'b1;

        // Deterministic cases.
        run_case(
            32'd0,
            32'd0,
            OPENFHE_Q
        );

        run_case(
            32'd1,
            32'd1,
            OPENFHE_Q
        );

        run_case(
            32'd7,
            32'd8,
            OPENFHE_Q
        );

        run_case(
            OPENFHE_Q - 1,
            OPENFHE_Q - 1,
            OPENFHE_Q
        );

        run_case(
            OPENFHE_Q - 2,
            32'hffffffff,
            OPENFHE_Q
        );

        run_case(
            32'hffffffff,
            32'hffffffff,
            32'd0
        );

        // Randomized cases.
        for (i = 0; i < 1000; i = i + 1)
        begin
            a = $urandom % OPENFHE_Q;
            b = $urandom;

            run_case(
                a,
                b,
                OPENFHE_Q
            );
        end

        $display(
            "PASS: %0d modular multiplications verified",
            test_count
        );

        $finish;
    end

endmodule
