`timescale 1ns/1ps

module tb_poly_mul16_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    localparam integer RANDOM_POLYNOMIAL_TESTS =
        20;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;
    logic start   = 1'b0;

    logic        load_we   = 1'b0;
    logic        load_bank = 1'b0;
    logic [3:0]  load_addr = 4'd0;
    logic [31:0] load_data = 32'd0;

    logic [3:0]  read_addr = 4'd0;
    logic [31:0] read_data;

    logic busy;
    logic done;

    logic done_seen;
    logic clear_done_seen = 1'b0;

    logic [31:0] source_a [0:15];
    logic [31:0] source_b [0:15];

    logic [31:0] expected [0:15];
    logic [31:0] golden_convolution [0:15];

    logic [63:0] reference_product;
    logic [63:0] reference_value;

    integer i;
    integer j;
    integer destination;

    integer case_number;
    integer random_seed;
    integer seed_sink;

    poly_mul16_core dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (start),

        .load_we   (load_we),
        .load_bank (load_bank),
        .load_addr (load_addr),
        .load_data (load_data),

        .read_addr (read_addr),
        .read_data (read_data),

        .busy      (busy),
        .done      (done)
    );

    always #5 clk = ~clk;

    /*
     * Preserve the one-clock completion pulse until the current
     * polynomial result has been checked.
     */
    always @(posedge clk)
    begin
        if (!reset_n || clear_done_seen)
            done_seen <= 1'b0;
        else if (done)
            done_seen <= 1'b1;
    end

    /*
     * Compute a software-reference negacyclic product:
     *
     *     C(X) = A(X)B(X) mod (X^16 + 1, q)
     *
     * Terms with degree 16 or greater wrap with a negative sign.
     */
    task automatic compute_reference;
        integer left_index;
        integer right_index;
        integer output_index;

        begin
            for (
                output_index = 0;
                output_index < 16;
                output_index = output_index + 1
            )
            begin
                expected[output_index] = 32'd0;
            end

            for (
                left_index = 0;
                left_index < 16;
                left_index = left_index + 1
            )
            begin
                for (
                    right_index = 0;
                    right_index < 16;
                    right_index = right_index + 1
                )
                begin
                    reference_product =
                        {32'd0, source_a[left_index]} *
                        {32'd0, source_b[right_index]};

                    reference_product =
                        reference_product % OPENFHE_Q;

                    destination =
                        left_index + right_index;

                    if (destination < 16)
                    begin
                        reference_value =
                            {32'd0, expected[destination]} +
                            reference_product;

                        expected[destination] =
                            reference_value % OPENFHE_Q;
                    end
                    else
                    begin
                        destination =
                            destination - 16;

                        reference_value =
                            {32'd0, expected[destination]} +
                            {32'd0, OPENFHE_Q} -
                            reference_product;

                        expected[destination] =
                            reference_value % OPENFHE_Q;
                    end
                end
            end
        end
    endtask

    task automatic run_current_case(
        input integer test_number,
        input integer print_success
    );
        integer address;
        integer timeout_cycles;

        begin
            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: polynomial multiplier busy before test %0d",
                    test_number
                );
                $fatal(1);
            end

            @(negedge clk);
            clear_done_seen = 1'b1;

            @(negedge clk);
            clear_done_seen = 1'b0;

            /*
             * Load polynomial A.
             */
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                if (source_a[address] >= OPENFHE_Q)
                begin
                    $display(
                        "INVALID A test=%0d address=%0d value=%0d",
                        test_number,
                        address,
                        source_a[address]
                    );
                    $fatal(1);
                end

                @(negedge clk);

                load_we   = 1'b1;
                load_bank = 1'b0;
                load_addr = address;
                load_data = source_a[address];
            end

            /*
             * Load polynomial B.
             */
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                if (source_b[address] >= OPENFHE_Q)
                begin
                    $display(
                        "INVALID B test=%0d address=%0d value=%0d",
                        test_number,
                        address,
                        source_b[address]
                    );
                    $fatal(1);
                end

                @(negedge clk);

                load_we   = 1'b1;
                load_bank = 1'b1;
                load_addr = address;
                load_data = source_b[address];
            end

            @(negedge clk);
            load_we = 1'b0;

            /*
             * Start the complete:
             *
             * forward A -> forward B -> pointwise -> inverse
             *
             * pipeline.
             */
            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            timeout_cycles = 0;

            while (
                (done_seen !== 1'b1) &&
                (timeout_cycles < 10000)
            )
            begin
                @(negedge clk);
                timeout_cycles = timeout_cycles + 1;
            end

            if (done_seen !== 1'b1)
            begin
                $display(
                    "TIMEOUT test=%0d cycles=%0d busy=%0b",
                    test_number,
                    timeout_cycles,
                    busy
                );
                $fatal(1);
            end

            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: busy remained asserted after test %0d",
                    test_number
                );
                $fatal(1);
            end

            /*
             * Compare the natural-order product coefficients.
             */
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                read_addr = address;
                #1;

                if (read_data !== expected[address])
                begin
                    $display(
                        "FAIL PRODUCT test=%0d address=%0d result=%0d expected=%0d",
                        test_number,
                        address,
                        read_data,
                        expected[address]
                    );
                    $fatal(1);
                end
            end

            if (print_success)
            begin
                $display(
                    "PASS: complete OpenFHE-profile negacyclic product matches golden model"
                );

                $display(
                    "Golden-vector observed cycles: %0d",
                    timeout_cycles
                );
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../model/golden/input_a.mem",
            source_a
        );

        $readmemh(
            "../model/golden/input_b.mem",
            source_b
        );

        $readmemh(
            "../model/golden/convolution.mem",
            golden_convolution
        );

        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * The first case is checked against the Python-generated
         * golden convolution.
         */
        for (i = 0; i < 16; i = i + 1)
        begin
            expected[i] = golden_convolution[i];
        end

        run_current_case(0, 1);

        /*
         * Seed the simulator's pseudorandom sequence.
         */
        random_seed = 32'h00c0ffee;
        seed_sink = $urandom(random_seed);

        /*
         * Validate randomized complete polynomial multiplications
         * against an independently computed schoolbook reference.
         */
        for (
            case_number = 1;
            case_number <= RANDOM_POLYNOMIAL_TESTS;
            case_number = case_number + 1
        )
        begin
            for (i = 0; i < 16; i = i + 1)
            begin
                source_a[i] =
                    $urandom % OPENFHE_Q;

                source_b[i] =
                    $urandom % OPENFHE_Q;
            end

            compute_reference();

            run_current_case(
                case_number,
                0
            );
        end

        $display(
            "PASS: %0d randomized complete negacyclic polynomial products",
            RANDOM_POLYNOMIAL_TESTS
        );

        $display(
            "PASS: forward NTT, pointwise multiplication, and inverse NTT agree"
        );

        $display(
            "Ring: Z_q[X] / (X^16 + 1)"
        );

        $display(
            "OpenFHE modulus: %0d",
            OPENFHE_Q
        );

        $display(
            "Modular multiplications per polynomial product: 112"
        );

        $finish;
    end

endmodule
