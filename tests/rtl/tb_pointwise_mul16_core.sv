`timescale 1ns/1ps

module tb_pointwise_mul16_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    localparam integer RANDOM_POLYNOMIAL_TESTS =
        100;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;
    logic start   = 1'b0;

    logic [31:0] q = OPENFHE_Q;

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

    logic [63:0] reference_product;

    integer i;
    integer case_number;
    integer random_seed;

    pointwise_mul16_core dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (start),

        .q         (q),

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
     * Preserve the one-clock completion pulse until the test task
     * has checked all sixteen output coefficients.
     */
    always @(posedge clk)
    begin
        if (!reset_n || clear_done_seen)
            done_seen <= 1'b0;
        else if (done)
            done_seen <= 1'b1;
    end

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
                    "FAIL: pointwise engine busy before test %0d",
                    test_number
                );
                $fatal(1);
            end

            /*
             * Clear completion state from any previous operation.
             */
            @(negedge clk);
            clear_done_seen = 1'b1;

            @(negedge clk);
            clear_done_seen = 1'b0;

            /*
             * Load input polynomial A.
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
             * Load input polynomial B.
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
             * Start all sixteen pointwise modular products.
             */
            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            timeout_cycles = 0;

            while (
                (done_seen !== 1'b1) &&
                (timeout_cycles < 2000)
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
             * Compare all sixteen pointwise products.
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
                        "FAIL POINTWISE test=%0d address=%0d a=%0d b=%0d result=%0d expected=%0d",
                        test_number,
                        address,
                        source_a[address],
                        source_b[address],
                        read_data,
                        expected[address]
                    );
                    $fatal(1);
                end
            end

            if (print_success)
            begin
                $display(
                    "PASS: OpenFHE golden pointwise product matches all 16 coefficients"
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
        /*
         * Load the forward transforms and expected pointwise product
         * produced by the Python golden model.
         */
        $readmemh(
            "../model/golden/forward_a.mem",
            source_a
        );

        $readmemh(
            "../model/golden/forward_b.mem",
            source_b
        );

        $readmemh(
            "../model/golden/pointwise.mem",
            expected
        );

        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        run_current_case(0, 1);

        /*
         * Validate complete random transform-domain vectors.
         */
        random_seed = 32'h00c0ffee;
        i = $urandom(random_seed);

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

                reference_product =
                    {32'd0, source_a[i]} *
                    {32'd0, source_b[i]};

                expected[i] =
                    reference_product % OPENFHE_Q;
            end

            run_current_case(
                case_number,
                0
            );
        end

        $display(
            "PASS: %0d randomized 16-coefficient pointwise products",
            RANDOM_POLYNOMIAL_TESTS
        );

        $display(
            "OpenFHE modulus: %0d",
            OPENFHE_Q
        );

        $display(
            "Modular multiplications per operation: 16"
        );

        $finish;
    end

endmodule
