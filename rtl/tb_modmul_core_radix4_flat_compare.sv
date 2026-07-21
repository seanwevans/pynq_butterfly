`timescale 1ns/1ps

module tb_modmul_core_radix4_flat_compare;

    localparam integer RANDOM_TESTS =
        10000;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic [31:0] a =
        32'd0;

    logic [31:0] b =
        32'd0;

    logic [31:0] q =
        32'd0;

    logic [31:0] baseline_result;
    logic baseline_busy;
    logic baseline_done;

    logic [31:0] radix4_result;
    logic radix4_busy;
    logic radix4_done;

    integer test_number;
    integer baseline_latency;
    integer radix4_latency;

    integer random_seed;
    integer seed_sink;

    logic [31:0] random_q;
    logic [31:0] random_a;
    logic [31:0] random_b;

    modmul_core_radix2 baseline (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (start),

        .a       (a),
        .b       (b),
        .q       (q),

        .result  (baseline_result),
        .busy    (baseline_busy),
        .done    (baseline_done)
    );

    modmul_core_radix4_flat candidate (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (start),

        .a       (a),
        .b       (b),
        .q       (q),

        .result  (radix4_result),
        .busy    (radix4_busy),
        .done    (radix4_done)
    );

    always #5 clk = ~clk;

    task automatic run_zero_modulus_case;
        begin
            @(negedge clk);

            a =
                32'hdeadbeef;

            b =
                32'h12345678;

            q =
                32'd0;

            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            if (
                baseline_busy !== 1'b0 ||
                baseline_done !== 1'b1 ||
                baseline_result !== 32'd0
            )
            begin
                $display(
                    "FAIL: baseline q=0 behavior"
                );

                $fatal(1);
            end

            if (
                radix4_busy !== 1'b0 ||
                radix4_done !== 1'b1 ||
                radix4_result !== 32'd0
            )
            begin
                $display(
                    "FAIL: radix-4 q=0 behavior"
                );

                $fatal(1);
            end

            @(posedge clk);
            @(negedge clk);

            if (
                baseline_done !== 1'b0 ||
                radix4_done !== 1'b0
            )
            begin
                $display(
                    "FAIL: q=0 completion was not a one-clock pulse"
                );

                $fatal(1);
            end

            $display(
                "PASS: q=0 interface behavior"
            );
        end
    endtask

    task automatic run_case(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [31:0] test_q,
        input integer case_number
    );
        logic [63:0] wide_product;
        logic [31:0] expected;

        integer baseline_finished;
        integer radix4_finished;

        begin
            if (test_q == 32'd0)
            begin
                $display(
                    "FAIL: run_case received q=0"
                );

                $fatal(1);
            end

            if (
                test_a >= test_q ||
                test_b >= test_q
            )
            begin
                $display(
                    "FAIL: unreduced test input case=%0d a=%0d b=%0d q=%0d",
                    case_number,
                    test_a,
                    test_b,
                    test_q
                );

                $fatal(1);
            end

            wide_product =
                {32'd0, test_a}
                * {32'd0, test_b};

            expected =
                wide_product % test_q;

            @(negedge clk);

            a =
                test_a;

            b =
                test_b;

            q =
                test_q;

            start =
                1'b1;

            /*
             * Both implementations accept the request here.
             */
            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            if (
                baseline_busy !== 1'b1 ||
                radix4_busy !== 1'b1
            )
            begin
                $display(
                    "FAIL: busy missing after start case=%0d baseline=%0b radix4=%0b",
                    case_number,
                    baseline_busy,
                    radix4_busy
                );

                $fatal(1);
            end

            baseline_latency =
                0;

            radix4_latency =
                0;

            baseline_finished =
                0;

            radix4_finished =
                0;

            while (
                !baseline_finished ||
                !radix4_finished
            )
            begin
                @(posedge clk);
                @(negedge clk);

                if (!baseline_finished)
                begin
                    baseline_latency =
                        baseline_latency + 1;

                    if (baseline_done)
                    begin
                        baseline_finished =
                            1;

                        if (baseline_busy !== 1'b0)
                        begin
                            $display(
                                "FAIL: baseline done while busy case=%0d",
                                case_number
                            );

                            $fatal(1);
                        end
                    end
                end

                if (!radix4_finished)
                begin
                    radix4_latency =
                        radix4_latency + 1;

                    if (radix4_done)
                    begin
                        radix4_finished =
                            1;

                        if (radix4_busy !== 1'b0)
                        begin
                            $display(
                                "FAIL: radix-4 done while busy case=%0d",
                                case_number
                            );

                            $fatal(1);
                        end
                    end
                end

                if (
                    baseline_latency > 40 ||
                    radix4_latency > 40
                )
                begin
                    $display(
                        "TIMEOUT case=%0d baseline=%0d radix4=%0d",
                        case_number,
                        baseline_latency,
                        radix4_latency
                    );

                    $fatal(1);
                end
            end

            if (baseline_latency != 32)
            begin
                $display(
                    "FAIL BASELINE LATENCY case=%0d result=%0d expected=32",
                    case_number,
                    baseline_latency
                );

                $fatal(1);
            end

            if (radix4_latency != 16)
            begin
                $display(
                    "FAIL RADIX4 LATENCY case=%0d result=%0d expected=16",
                    case_number,
                    radix4_latency
                );

                $fatal(1);
            end

            if (baseline_result !== expected)
            begin
                $display(
                    "FAIL BASELINE RESULT case=%0d a=%0d b=%0d q=%0d result=%0d expected=%0d",
                    case_number,
                    test_a,
                    test_b,
                    test_q,
                    baseline_result,
                    expected
                );

                $fatal(1);
            end

            if (radix4_result !== expected)
            begin
                $display(
                    "FAIL RADIX4 RESULT case=%0d a=%0d b=%0d q=%0d result=%0d expected=%0d",
                    case_number,
                    test_a,
                    test_b,
                    test_q,
                    radix4_result,
                    expected
                );

                $fatal(1);
            end

            if (baseline_result !== radix4_result)
            begin
                $display(
                    "FAIL IMPLEMENTATION DISAGREEMENT case=%0d baseline=%0d radix4=%0d",
                    case_number,
                    baseline_result,
                    radix4_result
                );

                $fatal(1);
            end

            /*
             * Completion must clear on the following clock.
             */
            @(posedge clk);
            @(negedge clk);

            if (
                baseline_done !== 1'b0 ||
                radix4_done !== 1'b0
            )
            begin
                $display(
                    "FAIL: completion pulse persisted case=%0d",
                    case_number
                );

                $fatal(1);
            end
        end
    endtask

    initial
    begin
        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        repeat (2) @(posedge clk);

        run_zero_modulus_case();

        /*
         * Fixed boundary and profile cases.
         */
        run_case(
            32'd0,
            32'd0,
            32'd1,
            0
        );

        run_case(
            32'd1,
            32'd1,
            32'd2,
            1
        );

        run_case(
            32'd2,
            32'd2,
            32'd3,
            2
        );

        run_case(
            32'd16,
            32'd16,
            32'd17,
            3
        );

        run_case(
            32'd1073692672,
            32'd1073692672,
            32'd1073692673,
            4
        );

        run_case(
            32'd236231,
            32'd628150263,
            32'd1073692673,
            5
        );

        run_case(
            32'hfffffffe,
            32'hfffffffe,
            32'hffffffff,
            6
        );

        run_case(
            32'h80000000,
            32'h7fffffff,
            32'hffffffff,
            7
        );

        $display(
            "PASS: fixed boundary and OpenFHE-profile cases"
        );

        random_seed =
            32'h5eedc0de;

        seed_sink =
            $urandom(random_seed);

        for (
            test_number = 0;
            test_number < RANDOM_TESTS;
            test_number = test_number + 1
        )
        begin
            random_q =
                $urandom;

            if (random_q == 32'd0)
            begin
                random_q =
                    32'd1;
            end

            random_a =
                $urandom % random_q;

            random_b =
                $urandom % random_q;

            run_case(
                random_a,
                random_b,
                random_q,
                test_number + 8
            );
        end

        $display(
            "PASS: %0d randomized reduced-residue products",
            RANDOM_TESTS
        );

        $display(
            "PASS: baseline and radix-4 results agree exactly"
        );

        $display(
            "Baseline arithmetic iterations: 32"
        );

        $display(
            "Radix-4 arithmetic iterations: 16"
        );

        $display(
            "PASS: radix-4 modular multiplier candidate verified"
        );

        $finish;
    end

endmodule
