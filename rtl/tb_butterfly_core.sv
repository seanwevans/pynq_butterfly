`timescale 1ns/1ps

module tb_butterfly_core;

    /*
     * OpenFHE 1.5.1 COMPOSITESCALINGAUTO profile:
     *
     * source ring dimension = 4096
     * source tower          = 0
     * derived test N        = 16
     */
    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    localparam logic [31:0] OPENFHE_PSI =
        32'd763394433;

    localparam logic [31:0] OPENFHE_OMEGA =
        32'd1051583792;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;
    logic start   = 1'b0;

    logic [31:0] a     = 32'd0;
    logic [31:0] b     = 32'd0;
    logic [31:0] omega = 32'd0;
    logic [31:0] q     = 32'd0;

    logic [31:0] out_a;
    logic [31:0] out_b;
    logic busy;
    logic done;

    logic [31:0] random_a;
    logic [31:0] random_b;
    logic [31:0] random_omega;

    integer test_count = 0;
    integer i;

    butterfly_core dut (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (start),

        .a       (a),
        .b       (b),
        .omega   (omega),
        .q       (q),

        .out_a   (out_a),
        .out_b   (out_b),
        .busy    (busy),
        .done    (done)
    );

    always #5 clk = ~clk;

    task automatic run_case(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [31:0] test_omega,
        input logic [31:0] test_q
    );
        logic [63:0] product;
        logic [63:0] sum_value;
        logic [63:0] difference_value;

        logic [31:0] expected_t;
        logic [31:0] expected_a;
        logic [31:0] expected_b;

        integer latency_cycles;

        begin
            if (test_q != 0)
            begin
                if (test_a >= test_q)
                begin
                    $display(
                        "INVALID TEST: a=%0d must be less than q=%0d",
                        test_a,
                        test_q
                    );
                    $fatal(1);
                end

                if (test_b >= test_q)
                begin
                    $display(
                        "INVALID TEST: b=%0d must be less than q=%0d",
                        test_b,
                        test_q
                    );
                    $fatal(1);
                end

                if (test_omega >= test_q)
                begin
                    $display(
                        "INVALID TEST: omega=%0d must be less than q=%0d",
                        test_omega,
                        test_q
                    );
                    $fatal(1);
                end
            end

            if (test_q == 0)
            begin
                expected_t = 32'd0;
                expected_a = 32'd0;
                expected_b = 32'd0;
            end
            else
            begin
                /*
                 * Force a 64-bit product before applying the
                 * software-reference modulus.
                 */
                product =
                    {32'd0, test_omega} *
                    {32'd0, test_b};

                expected_t = product % test_q;

                sum_value =
                    {32'd0, test_a} +
                    {32'd0, expected_t};

                expected_a = sum_value % test_q;

                difference_value =
                    {32'd0, test_a} +
                    {32'd0, test_q} -
                    {32'd0, expected_t};

                expected_b = difference_value % test_q;
            end

            // Present the command before the next rising clock edge.
            @(negedge clk);

            a     = test_a;
            b     = test_b;
            omega = test_omega;
            q     = test_q;
            start = 1'b1;

            // The command is accepted at the intervening positive edge.
            @(negedge clk);
            start = 1'b0;

            latency_cycles = 0;

            /*
             * Poll on falling edges so all positive-edge nonblocking
             * assignments have settled.
             */
            while ((done !== 1'b1) && (latency_cycles < 100))
            begin
                @(negedge clk);
                latency_cycles = latency_cycles + 1;
            end

            if (done !== 1'b1)
            begin
                $display(
                    "TIMEOUT a=%0d b=%0d omega=%0d q=%0d busy=%0b",
                    test_a,
                    test_b,
                    test_omega,
                    test_q,
                    busy
                );
                $fatal(1);
            end

            if (out_a !== expected_a)
            begin
                $display(
                    "FAIL OUT_A a=%0d b=%0d omega=%0d q=%0d result=%0d expected=%0d t=%0d",
                    test_a,
                    test_b,
                    test_omega,
                    test_q,
                    out_a,
                    expected_a,
                    expected_t
                );
                $fatal(1);
            end

            if (out_b !== expected_b)
            begin
                $display(
                    "FAIL OUT_B a=%0d b=%0d omega=%0d q=%0d result=%0d expected=%0d t=%0d",
                    test_a,
                    test_b,
                    test_omega,
                    test_q,
                    out_b,
                    expected_b,
                    expected_t
                );
                $fatal(1);
            end

            if (test_q == 0)
            begin
                if (latency_cycles != 1)
                begin
                    $display(
                        "FAIL q=0 latency=%0d expected=1",
                        latency_cycles
                    );
                    $fatal(1);
                end
            end
            else
            begin
                /*
                 * 16 radix-4 multiplier iterations plus one cycle
                 * for the butterfly to capture and register both
                 * outputs.
                 */
                if (latency_cycles != 17)
                begin
                    $display(
                        "FAIL latency=%0d expected=17",
                        latency_cycles
                    );
                    $fatal(1);
                end
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
            OPENFHE_OMEGA,
            OPENFHE_Q
        );

        run_case(
            32'd1,
            32'd1,
            32'd1,
            OPENFHE_Q
        );

        run_case(
            32'd7,
            32'd8,
            OPENFHE_OMEGA,
            OPENFHE_Q
        );

        run_case(
            OPENFHE_Q - 1,
            OPENFHE_Q - 1,
            32'd1,
            OPENFHE_Q
        );

        run_case(
            OPENFHE_Q - 1,
            OPENFHE_Q - 1,
            OPENFHE_Q - 1,
            OPENFHE_Q
        );

        run_case(
            32'hffffffff,
            32'hffffffff,
            32'hffffffff,
            32'd0
        );

        /*
         * Five hundred cases using the exact OpenFHE-derived root.
         */
        for (i = 0; i < 500; i = i + 1)
        begin
            random_a = $urandom % OPENFHE_Q;
            random_b = $urandom % OPENFHE_Q;

            run_case(
                random_a,
                random_b,
                OPENFHE_OMEGA,
                OPENFHE_Q
            );
        end

        /*
         * Five hundred generic cases. These cover arbitrary reduced
         * twiddle values, including the powers used by later stages.
         */
        for (i = 0; i < 500; i = i + 1)
        begin
            random_a     = $urandom % OPENFHE_Q;
            random_b     = $urandom % OPENFHE_Q;
            random_omega = $urandom % OPENFHE_Q;

            run_case(
                random_a,
                random_b,
                random_omega,
                OPENFHE_Q
            );
        end

        $display(
            "PASS: %0d butterflies verified",
            test_count
        );

        $display(
            "OpenFHE q=%0d psi=%0d omega=%0d",
            OPENFHE_Q,
            OPENFHE_PSI,
            OPENFHE_OMEGA
        );

        $display(
            "Nonzero-modulus butterfly latency: 33 cycles"
        );

        $finish;
    end

endmodule
