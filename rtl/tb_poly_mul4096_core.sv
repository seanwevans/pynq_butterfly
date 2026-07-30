`timescale 1ns/1ps

module tb_poly_mul4096_core;

    localparam integer N =
        4096;

    localparam logic [31:0] EXPECTED_PRODUCT_CYCLES =
        32'd1376268;

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

    logic [11:0] read_addr =
        12'd0;

    logic [31:0] read_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [16:0] multiplication_count;

    logic [31:0] forward_cycles;
    logic [31:0] pointwise_cycles;
    logic [31:0] inverse_cycles;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];
    logic [31:0] expected_convolution [0:N-1];

    logic [31:0] first_cycles;

    integer address;

    poly_mul4096_core dut (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (start),

        .load_a_we            (load_a_we),
        .load_a_addr          (load_a_addr),
        .load_a_data          (load_a_data),

        .load_b_we            (load_b_we),
        .load_b_addr          (load_b_addr),
        .load_b_data          (load_b_data),

        .read_addr            (read_addr),
        .read_data            (read_data),

        .busy                 (busy),
        .done                 (done),

        .cycles               (cycles),
        .multiplication_count (multiplication_count),

        .forward_cycles       (forward_cycles),
        .pointwise_cycles     (pointwise_cycles),
        .inverse_cycles       (inverse_cycles)
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

            if (
                busy
                || multiplication_count != 17'd90112
            )
            begin
                $display(
                    "FAIL COMPLETION busy=%0b multiplications=%0d",
                    busy,
                    multiplication_count
                );

                $fatal(1);
            end

            if (
                forward_cycles != 32'd626691
                || pointwise_cycles != 32'd86016
                || inverse_cycles != 32'd638979
            )
            begin
                $display(
                    "FAIL PHASE CYCLES forward=%0d pointwise=%0d inverse=%0d",
                    forward_cycles,
                    pointwise_cycles,
                    inverse_cycles
                );

                $fatal(1);
            end

            if (cycles !== EXPECTED_PRODUCT_CYCLES)
            begin
                $display(
                    "FAIL PRODUCT CYCLES result=%0d expected=%0d",
                    cycles,
                    EXPECTED_PRODUCT_CYCLES
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

                read_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (
                    read_data
                    !== expected_convolution[address]
                )
                begin
                    $display(
                        "FAIL PRODUCT address=%0d result=%0d expected=%0d",
                        address,
                        read_data,
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

        load_inputs();
        run_product();
        compare_result();

        first_cycles =
            cycles;

        $display(
            "PASS: complete N=4096 negacyclic polynomial product matches golden model"
        );

        $display(
            "Complete hardware-controller cycles: %0d",
            cycles
        );

        load_inputs();
        run_product();
        compare_result();

        if (cycles !== first_cycles)
        begin
            $display(
                "FAIL CONSTANT TIME first=%0d second=%0d",
                first_cycles,
                cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: repeated complete N=4096 polynomial product"
        );

        $display(
            "PASS: forward, pointwise, and inverse phases agree"
        );

        $display(
            "PASS: complete polynomial-product timing is constant"
        );

        $display(
            "Ring: Z_q[X] / (X^4096 + 1)"
        );

        $display(
            "Modulus: 1073692673"
        );

        $display(
            "Parallel forward-transform cycles: %0d",
            forward_cycles
        );

        $display(
            "Pointwise cycles: %0d",
            pointwise_cycles
        );

        $display(
            "Inverse-transform cycles: %0d",
            inverse_cycles
        );

        $display(
            "Constant product cycles: %0d",
            first_cycles
        );

        $display(
            "Modular multiplications per polynomial product: %0d",
            multiplication_count
        );

        $finish;
    end

endmodule
