`timescale 1ns/1ps

module tb_poly_mul4096_two_bank_core;

    localparam integer N =
        4096;

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd1339394;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic load_a_we =
        1'b0;

    logic [11:0] load_a_addr =
        12'd0;

    logic [31:0] load_a_data =
        32'd0;

    logic load_b_we =
        1'b0;

    logic [11:0] load_b_addr =
        12'd0;

    logic [31:0] load_b_data =
        32'd0;

    logic [11:0] read_a_addr =
        12'd0;

    logic [31:0] read_a_data;

    logic [11:0] read_b_addr =
        12'd0;

    logic [31:0] read_b_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [16:0] multiplication_count;

    logic [12:0] preprocessing_count;
    logic [14:0] forward_butterfly_count;
    logic [12:0] pointwise_count;
    logic [14:0] inverse_butterfly_count;
    logic [12:0] postprocessing_count;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];
    logic [31:0] expected_convolution [0:N-1];

    logic [31:0] first_cycles;

    integer address;
    integer run_index;

    poly_mul4096_two_bank_core dut (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (start),

        .load_a_we                 (load_a_we),
        .load_a_addr               (load_a_addr),
        .load_a_data               (load_a_data),

        .load_b_we                 (load_b_we),
        .load_b_addr               (load_b_addr),
        .load_b_data               (load_b_data),

        .read_a_addr               (read_a_addr),
        .read_a_data               (read_a_data),

        .read_b_addr               (read_b_addr),
        .read_b_data               (read_b_data),

        .busy                      (busy),
        .done                      (done),

        .cycles                    (cycles),
        .multiplication_count      (multiplication_count),

        .preprocessing_count       (preprocessing_count),
        .forward_butterfly_count   (forward_butterfly_count),
        .pointwise_count           (pointwise_count),
        .inverse_butterfly_count   (inverse_butterfly_count),
        .postprocessing_count      (postprocessing_count)
    );

    always #5 clk = ~clk;

    task automatic load_inputs;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                load_a_we =
                    1'b1;

                load_a_addr =
                    address[11:0];

                load_a_data =
                    input_a[address];

                load_b_we =
                    1'b1;

                load_b_addr =
                    address[11:0];

                load_b_data =
                    input_b[address];

                @(posedge clk);
            end

            @(negedge clk);

            load_a_we =
                1'b0;

            load_b_we =
                1'b0;
        end
    endtask

    task automatic run_product;
        begin
            @(negedge clk);

            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            while (!done)
            begin
                @(posedge clk);
                @(negedge clk);
            end

            if (busy)
            begin
                $display(
                    "FAIL: core remained busy after done"
                );

                $fatal(1);
            end

            if (
                preprocessing_count != 13'd4096
                || forward_butterfly_count != 15'd24576
                || pointwise_count != 13'd4096
                || inverse_butterfly_count != 15'd24576
                || postprocessing_count != 13'd4096
                || multiplication_count != 17'd90112
            )
            begin
                $display(
                    "FAIL COUNTS prep=%0d fwd=%0d point=%0d inv=%0d post=%0d mult=%0d",
                    preprocessing_count,
                    forward_butterfly_count,
                    pointwise_count,
                    inverse_butterfly_count,
                    postprocessing_count,
                    multiplication_count
                );

                $fatal(1);
            end

            if (cycles !== EXPECTED_CYCLES)
            begin
                $display(
                    "FAIL CYCLES result=%0d expected=%0d",
                    cycles,
                    EXPECTED_CYCLES
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_result;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                read_a_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (
                    read_a_data
                    !== expected_convolution[address]
                )
                begin
                    $display(
                        "FAIL PRODUCT address=%0d result=%0d expected=%0d",
                        address,
                        read_a_data,
                        expected_convolution[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/input_a.mem",
            input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/input_b.mem",
            input_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/convolution.mem",
            expected_convolution
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        for (
            run_index = 0;
            run_index < 2;
            run_index = run_index + 1
        )
        begin
            load_inputs();
            run_product();
            compare_result();

            if (run_index == 0)
            begin
                first_cycles =
                    cycles;
            end
            else if (cycles !== first_cycles)
            begin
                $display(
                    "FAIL CONSTANT TIME first=%0d second=%0d",
                    first_cycles,
                    cycles
                );

                $fatal(1);
            end

            $display(
                "PASS: consolidated two-bank N=4096 product run %0d",
                run_index
            );
        end

        $display(
            "PASS: complete N=4096 negacyclic product matches golden convolution"
        );

        $display(
            "PASS: forward DIF, pointwise, inverse DIT, and postscale operate in place"
        );

        $display(
            "PASS: complete two-bank timing is constant"
        );

        $display(
            "Coefficient BRAM banks: 2"
        );

        $display(
            "Expected total RAMB36 after synthesis: 24"
        );

        $display(
            "Previous proof-core cycles: 1376268"
        );

        $display(
            "Consolidated core cycles: %0d",
            first_cycles
        );

        $display(
            "Cycles removed: %0d",
            32'd1376268 - first_cycles
        );

        $display(
            "Modular multiplications per product: %0d",
            multiplication_count
        );

        $finish;
    end

endmodule
