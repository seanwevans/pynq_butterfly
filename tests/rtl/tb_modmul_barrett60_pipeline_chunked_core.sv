`timescale 1ns/1ps

module tb_modmul_barrett60_pipeline_chunked_core;

    localparam integer PIPELINE_LATENCY =
        9;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [30:0] MU0 =
        31'h4000c001;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    localparam logic [30:0] MU1 =
        31'h40012004;

    logic clk;
    logic reset_n;

    logic        input_valid;
    logic [31:0] a;
    logic [31:0] b;
    logic [31:0] q;
    logic [30:0] mu;

    logic        output_valid;
    logic [31:0] result;

    logic        expected_valid [0:PIPELINE_LATENCY];
    logic [31:0] expected_result[0:PIPELINE_LATENCY];

    integer sent_count;
    integer received_count;
    integer check_index;
    integer test_index;

    logic [31:0] selected_q;
    logic [30:0] selected_mu;
    logic [31:0] random_a;
    logic [31:0] random_b;

    modmul_barrett60_pipeline_chunked_core dut (
        .clk          (clk),
        .reset_n      (reset_n),

        .input_valid  (input_valid),
        .a            (a),
        .b            (b),
        .q            (q),
        .mu           (mu),

        .output_valid (output_valid),
        .result       (result)
    );

    function automatic [31:0] reference_modmul (
        input logic [31:0] function_a,
        input logic [31:0] function_b,
        input logic [31:0] function_q
    );
        logic [63:0] wide_product;
        begin
            wide_product =
                {32'd0, function_a}
                * {32'd0, function_b};

            reference_modmul =
                wide_product % function_q;
        end
    endfunction

    task automatic send_product (
        input logic [31:0] task_a,
        input logic [31:0] task_b,
        input logic [31:0] task_q,
        input logic [30:0] task_mu
    );
        begin
            @(negedge clk);

            input_valid =
                1'b1;

            a =
                task_a;

            b =
                task_b;

            q =
                task_q;

            mu =
                task_mu;

            sent_count =
                sent_count + 1;
        end
    endtask

    initial
    begin
        clk =
            1'b0;

        forever
        begin
            #5 clk =
                !clk;
        end
    end

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            for (
                check_index = 0;
                check_index <= PIPELINE_LATENCY;
                check_index = check_index + 1
            )
            begin
                expected_valid[check_index] <=
                    1'b0;

                expected_result[check_index] <=
                    32'd0;
            end
        end
        else
        begin
            expected_valid[0] <=
                input_valid;

            expected_result[0] <=
                input_valid
                    ? reference_modmul(a, b, q)
                    : 32'd0;

            for (
                check_index = 1;
                check_index <= PIPELINE_LATENCY;
                check_index = check_index + 1
            )
            begin
                expected_valid[check_index] <=
                    expected_valid[check_index - 1];

                expected_result[check_index] <=
                    expected_result[check_index - 1];
            end

            #1;

            if (
                output_valid
                !== expected_valid[PIPELINE_LATENCY]
            )
            begin
                $display(
                    "ERROR: valid mismatch expected=%0b actual=%0b",
                    expected_valid[PIPELINE_LATENCY],
                    output_valid
                );
                $fatal(1);
            end

            if (output_valid)
            begin
                if (
                    result
                    !== expected_result[PIPELINE_LATENCY]
                )
                begin
                    $display(
                        "ERROR: product mismatch expected=%0d actual=%0d",
                        expected_result[PIPELINE_LATENCY],
                        result
                    );
                    $fatal(1);
                end

                received_count =
                    received_count + 1;
            end
        end
    end

    initial
    begin
        reset_n =
            1'b0;

        input_valid =
            1'b0;

        a =
            32'd0;

        b =
            32'd0;

        q =
            Q0;

        mu =
            MU0;

        sent_count =
            0;

        received_count =
            0;

        repeat (4)
        begin
            @(posedge clk);
        end

        @(negedge clk);

        reset_n =
            1'b1;

        /*
         * Directed boundary cases.
         */
        send_product(32'd0, 32'd0, Q0, MU0);
        send_product(32'd0, Q0 - 1'b1, Q0, MU0);
        send_product(32'd1, 32'd1, Q0, MU0);
        send_product(Q0 - 1'b1, Q0 - 1'b1, Q0, MU0);
        send_product(Q0 - 2'd2, Q0 - 3'd3, Q0, MU0);

        send_product(32'd0, 32'd0, Q1, MU1);
        send_product(32'd0, Q1 - 1'b1, Q1, MU1);
        send_product(32'd1, 32'd1, Q1, MU1);
        send_product(Q1 - 1'b1, Q1 - 1'b1, Q1, MU1);
        send_product(Q1 - 2'd2, Q1 - 3'd3, Q1, MU1);

        /*
         * Continuous one-input-per-clock stream.
         */
        for (
            test_index = 0;
            test_index < 10000;
            test_index = test_index + 1
        )
        begin
            if (test_index[0])
            begin
                selected_q =
                    Q1;

                selected_mu =
                    MU1;
            end
            else
            begin
                selected_q =
                    Q0;

                selected_mu =
                    MU0;
            end

            random_a =
                $urandom_range(
                    selected_q - 1'b1,
                    0
                );

            random_b =
                $urandom_range(
                    selected_q - 1'b1,
                    0
                );

            send_product(
                random_a,
                random_b,
                selected_q,
                selected_mu
            );
        end

        @(negedge clk);

        input_valid =
            1'b0;

        a =
            32'd0;

        b =
            32'd0;

        repeat (PIPELINE_LATENCY + 3)
        begin
            @(posedge clk);
        end

        if (received_count != sent_count)
        begin
            $display(
                "ERROR: sent=%0d received=%0d",
                sent_count,
                received_count
            );
            $fatal(1);
        end

        $display(
            "PASS: %0d exact modular products; latency=%0d; II=1",
            received_count,
            PIPELINE_LATENCY
        );

        $finish;
    end

endmodule
