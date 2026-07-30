`timescale 1ns/1ps

module tb_pointwise_mul256_core;

    localparam integer N =
        256;

    localparam logic [31:0] Q =
        32'd1073692673;

    localparam integer RANDOM_TESTS =
        20;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic start = 1'b0;

    logic load_we = 1'b0;
    logic load_bank = 1'b0;
    logic [7:0] load_addr = 8'd0;
    logic [31:0] load_data = 32'd0;

    logic [7:0] read_addr = 8'd0;
    logic [31:0] read_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [8:0] multiplication_count;

    logic done_seen = 1'b0;
    logic clear_done_seen = 1'b0;

    logic [31:0] source_a [0:255];
    logic [31:0] source_b [0:255];
    logic [31:0] expected [0:255];

    logic [63:0] wide_product;

    logic [31:0] reference_cycles;

    integer address;
    integer test_number;
    integer timeout_cycles;

    integer random_seed;
    integer seed_sink;

    pointwise_mul256_core dut (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (start),

        .load_we              (load_we),
        .load_bank            (load_bank),
        .load_addr            (load_addr),
        .load_data            (load_data),

        .read_addr            (read_addr),
        .read_data            (read_data),

        .busy                 (busy),
        .done                 (done),

        .cycles               (cycles),
        .multiplication_count (multiplication_count)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
    begin
        if (!reset_n || clear_done_seen)
        begin
            done_seen <=
                1'b0;
        end
        else if (done)
        begin
            done_seen <=
                1'b1;
        end
    end

    task automatic clear_completion;
        begin
            @(negedge clk);

            clear_done_seen =
                1'b1;

            @(negedge clk);

            clear_done_seen =
                1'b0;
        end
    endtask

    task automatic load_vectors;
        begin
            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: pointwise engine busy before loading"
                );

                $fatal(1);
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                load_we =
                    1'b1;

                load_bank =
                    1'b0;

                load_addr =
                    address[7:0];

                load_data =
                    source_a[address];
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                load_we =
                    1'b1;

                load_bank =
                    1'b1;

                load_addr =
                    address[7:0];

                load_data =
                    source_b[address];
            end

            @(negedge clk);

            load_we =
                1'b0;
        end
    endtask

    task automatic compare_result(
        input integer current_test
    );
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                read_addr =
                    address[7:0];

                /*
                 * Result BRAM reads are synchronous.
                 */
                @(negedge clk);

                if (
                    read_data
                    !== expected[address]
                )
                begin
                    $display(
                        "FAIL POINTWISE test=%0d address=%0d result=%0d expected=%0d",
                        current_test,
                        address,
                        read_data,
                        expected[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    task automatic run_current_test(
        input integer current_test,
        input integer print_success
    );
        begin
            clear_completion();
            load_vectors();

            @(negedge clk);

            start =
                1'b1;

            @(negedge clk);

            start =
                1'b0;

            timeout_cycles =
                0;

            while (
                (done_seen !== 1'b1) &&
                (timeout_cycles < 20000)
            )
            begin
                @(negedge clk);

                timeout_cycles =
                    timeout_cycles + 1;
            end

            if (done_seen !== 1'b1)
            begin
                $display(
                    "TIMEOUT test=%0d cycles=%0d busy=%0b multiplications=%0d",
                    current_test,
                    timeout_cycles,
                    busy,
                    multiplication_count
                );

                $fatal(1);
            end

            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: pointwise engine remained busy"
                );

                $fatal(1);
            end

            if (
                multiplication_count
                !== 9'd256
            )
            begin
                $display(
                    "FAIL MULTIPLICATION COUNT result=%0d expected=256",
                    multiplication_count
                );

                $fatal(1);
            end

            compare_result(current_test);

            if (current_test == 0)
            begin
                reference_cycles =
                    cycles;
            end
            else if (cycles !== reference_cycles)
            begin
                $display(
                    "FAIL: data-dependent timing test=%0d result=%0d expected=%0d",
                    current_test,
                    cycles,
                    reference_cycles
                );

                $fatal(1);
            end

            if (print_success)
            begin
                $display(
                    "PASS: N=256 pointwise product matches golden model"
                );

                $display(
                    "Pointwise hardware-controller cycles: %0d",
                    cycles
                );
            end
        end
    endtask

    initial
    begin
        /*
         * First test: Python-generated transform-domain vectors.
         */
        $readmemh(
            "../tests/fixtures/ntt_n256/forward_a.mem",
            source_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/forward_b.mem",
            source_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/pointwise.mem",
            expected
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        run_current_test(
            0,
            1
        );

        random_seed =
            32'h00c0ffee;

        seed_sink =
            $urandom(random_seed);

        /*
         * Randomized complete transform-domain vectors.
         */
        for (
            test_number = 1;
            test_number <= RANDOM_TESTS;
            test_number = test_number + 1
        )
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                source_a[address] =
                    $urandom % Q;

                source_b[address] =
                    $urandom % Q;

                wide_product =
                    {32'd0, source_a[address]}
                    * {32'd0, source_b[address]};

                expected[address] =
                    wide_product % Q;
            end

            run_current_test(
                test_number,
                0
            );
        end

        $display(
            "PASS: %0d randomized N=256 pointwise vector products",
            RANDOM_TESTS
        );

        $display(
            "PASS: pointwise timing is constant across all test vectors"
        );

        $display(
            "Constant pointwise cycles: %0d",
            reference_cycles
        );

        $display(
            "Modular multiplications per pointwise product: 256"
        );

        $finish;
    end

endmodule
