`timescale 1ns/1ps

module tb_poly_mul256_core;

    localparam integer N =
        256;

    localparam logic [31:0] Q =
        32'd1073692673;

    localparam integer RANDOM_TESTS =
        3;

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
    logic [12:0] modular_multiplication_count;

    logic done_seen = 1'b0;
    logic clear_done_seen = 1'b0;

    logic [31:0] source_a [0:255];
    logic [31:0] source_b [0:255];

    logic [31:0] expected [0:255];
    logic [31:0] golden_convolution [0:255];

    logic [63:0] wide_product;
    logic [63:0] wide_value;
    logic [31:0] product_mod;

    logic [31:0] reference_cycles;

    integer address;
    integer left_index;
    integer right_index;
    integer destination;

    integer test_number;
    integer timeout_cycles;

    integer random_seed;
    integer seed_sink;

    poly_mul256_core dut (
        .clk                          (clk),
        .reset_n                      (reset_n),
        .start                        (start),

        .load_we                      (load_we),
        .load_bank                    (load_bank),
        .load_addr                    (load_addr),
        .load_data                    (load_data),

        .read_addr                    (read_addr),
        .read_data                    (read_data),

        .busy                         (busy),
        .done                         (done),

        .cycles                       (cycles),

        .modular_multiplication_count (
            modular_multiplication_count
        )
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

    task automatic compute_reference;
        begin
            for (
                destination = 0;
                destination < N;
                destination = destination + 1
            )
            begin
                expected[destination] =
                    32'd0;
            end

            for (
                left_index = 0;
                left_index < N;
                left_index = left_index + 1
            )
            begin
                for (
                    right_index = 0;
                    right_index < N;
                    right_index = right_index + 1
                )
                begin
                    wide_product =
                        {32'd0, source_a[left_index]}
                        * {32'd0, source_b[right_index]};

                    product_mod =
                        wide_product % Q;

                    destination =
                        left_index + right_index;

                    if (destination < N)
                    begin
                        wide_value =
                            {32'd0, expected[destination]}
                            + {32'd0, product_mod};

                        expected[destination] =
                            wide_value % Q;
                    end
                    else
                    begin
                        destination =
                            destination - N;

                        wide_value =
                            {32'd0, expected[destination]}
                            + {32'd0, Q}
                            - {32'd0, product_mod};

                        expected[destination] =
                            wide_value % Q;
                    end
                end
            end
        end
    endtask

    task automatic load_polynomials;
        begin
            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: polynomial multiplier busy before loading"
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
                 * Inverse result BRAM reads are synchronous.
                 */
                @(negedge clk);

                if (
                    read_data
                    !== expected[address]
                )
                begin
                    $display(
                        "FAIL PRODUCT test=%0d address=%0d result=%0d expected=%0d",
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
            load_polynomials();

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
                (timeout_cycles < 250000)
            )
            begin
                @(negedge clk);

                timeout_cycles =
                    timeout_cycles + 1;
            end

            if (done_seen !== 1'b1)
            begin
                $display(
                    "TIMEOUT test=%0d cycles=%0d busy=%0b modular_multiplications=%0d",
                    current_test,
                    timeout_cycles,
                    busy,
                    modular_multiplication_count
                );

                $fatal(1);
            end

            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: complete polynomial multiplier remained busy"
                );

                $fatal(1);
            end

            if (
                modular_multiplication_count
                !== 13'd4096
            )
            begin
                $display(
                    "FAIL MODULAR MULTIPLICATION COUNT result=%0d expected=4096",
                    modular_multiplication_count
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
                    "PASS: complete N=256 negacyclic polynomial product matches golden model"
                );

                $display(
                    "Complete hardware-controller cycles: %0d",
                    cycles
                );
            end
        end
    endtask

    initial
    begin
        /*
         * Golden OpenFHE-profile vector.
         */
        $readmemh(
            "../model/golden_n256/input_a.mem",
            source_a
        );

        $readmemh(
            "../model/golden_n256/input_b.mem",
            source_b
        );

        $readmemh(
            "../model/golden_n256/convolution.mem",
            golden_convolution
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            expected[address] =
                golden_convolution[address];
        end

        run_current_test(
            0,
            1
        );

        random_seed =
            32'h00c0ffee;

        seed_sink =
            $urandom(random_seed);

        /*
         * Independent randomized schoolbook checks.
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
            end

            compute_reference();

            run_current_test(
                test_number,
                0
            );
        end

        $display(
            "PASS: %0d randomized complete N=256 negacyclic products",
            RANDOM_TESTS
        );

        $display(
            "PASS: forward NTT, pointwise multiplication, and inverse NTT agree"
        );

        $display(
            "PASS: complete polynomial-product timing is constant"
        );

        $display(
            "Ring: Z_q[X] / (X^256 + 1)"
        );

        $display(
            "Modulus: %0d",
            Q
        );

        $display(
            "Constant product cycles: %0d",
            reference_cycles
        );

        $display(
            "Modular multiplications per polynomial product: 4096"
        );

        $finish;
    end

endmodule
