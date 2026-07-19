`timescale 1ns/1ps

module tb_poly_mul256_axis_batch_core;

    localparam integer BATCH_PRODUCTS =
        4;

    localparam integer BATCHES =
        2;

    localparam integer INPUT_WORDS_PER_PRODUCT =
        512;

    localparam integer OUTPUT_WORDS_PER_PRODUCT =
        256;

    localparam integer TOTAL_INPUT_WORDS =
        BATCH_PRODUCTS * INPUT_WORDS_PER_PRODUCT;

    localparam integer TOTAL_OUTPUT_WORDS =
        BATCH_PRODUCTS * OUTPUT_WORDS_PER_PRODUCT;

    localparam logic [31:0] EXPECTED_CORE_CYCLES =
        32'd159249;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic [31:0] s_axis_tdata =
        32'd0;

    logic [3:0] s_axis_tkeep =
        4'hf;

    logic s_axis_tvalid =
        1'b0;

    logic s_axis_tready;

    logic s_axis_tlast =
        1'b0;

    logic [31:0] m_axis_tdata;
    logic [3:0]  m_axis_tkeep;
    logic        m_axis_tvalid;

    logic m_axis_tready =
        1'b0;

    logic m_axis_tlast;

    logic busy;
    logic batch_done;
    logic protocol_error;

    logic [31:0] completed_products;
    logic [31:0] core_cycles;
    logic [12:0] modular_multiplication_count;

    logic [31:0] input_a [0:255];
    logic [31:0] input_b [0:255];
    logic [31:0] expected [0:255];

    integer batch_number;
    integer input_word;
    integer output_word;
    integer coefficient_index;

    integer gap_cycles;
    integer gap_index;
    integer timeout_cycles;

    integer random_seed;
    integer seed_sink;

    logic [31:0] current_input_value;

    poly_mul256_axis_batch_core #(
        .BATCH_PRODUCTS(
            BATCH_PRODUCTS
        ),

        .FORWARD_TWIST_INIT_FILE(
            "../model/golden_n256/twist_factors.mem"
        ),

        .FORWARD_TWIDDLE_INIT_FILE(
            "../model/golden_n256/forward_twiddles.mem"
        ),

        .INVERSE_TWIDDLE_INIT_FILE(
            "../model/golden_n256/inverse_twiddles.mem"
        ),

        .INVERSE_SCALE_INIT_FILE(
            "../model/golden_n256/inverse_scale_factors.mem"
        )
    ) dut (
        .aclk                         (clk),
        .aresetn                      (reset_n),

        .s_axis_tdata                 (s_axis_tdata),
        .s_axis_tkeep                 (s_axis_tkeep),
        .s_axis_tvalid                (s_axis_tvalid),
        .s_axis_tready                (s_axis_tready),
        .s_axis_tlast                 (s_axis_tlast),

        .m_axis_tdata                 (m_axis_tdata),
        .m_axis_tkeep                 (m_axis_tkeep),
        .m_axis_tvalid                (m_axis_tvalid),
        .m_axis_tready                (m_axis_tready),
        .m_axis_tlast                 (m_axis_tlast),

        .busy                         (busy),
        .batch_done                   (batch_done),
        .protocol_error               (protocol_error),

        .completed_products           (completed_products),
        .core_cycles                  (core_cycles),

        .modular_multiplication_count (
            modular_multiplication_count
        )
    );

    always #5 clk = ~clk;

    task automatic send_batch;
        integer word_within_product;

        begin
            for (
                input_word = 0;
                input_word < TOTAL_INPUT_WORDS;
                input_word = input_word + 1
            )
            begin
                gap_cycles =
                    $urandom % 4;

                for (
                    gap_index = 0;
                    gap_index < gap_cycles;
                    gap_index = gap_index + 1
                )
                begin
                    @(negedge clk);

                    s_axis_tvalid =
                        1'b0;

                    s_axis_tlast =
                        1'b0;
                end

                word_within_product =
                    input_word % INPUT_WORDS_PER_PRODUCT;

                if (word_within_product < 256)
                begin
                    current_input_value =
                        input_a[word_within_product];
                end
                else
                begin
                    current_input_value =
                        input_b[word_within_product - 256];
                end

                @(negedge clk);

                s_axis_tdata =
                    current_input_value;

                s_axis_tkeep =
                    4'hf;

                s_axis_tlast =
                    input_word == TOTAL_INPUT_WORDS - 1;

                s_axis_tvalid =
                    1'b1;

                do
                begin
                    @(posedge clk);
                end
                while (!(s_axis_tvalid && s_axis_tready));

                @(negedge clk);

                s_axis_tvalid =
                    1'b0;

                s_axis_tlast =
                    1'b0;
            end

            $display(
                "PASS: streamed %0d-word batched input packet",
                TOTAL_INPUT_WORDS
            );
        end
    endtask

    task automatic receive_batch(
        input integer current_batch
    );
        begin
            output_word =
                0;

            timeout_cycles =
                0;

            while (
                (output_word < TOTAL_OUTPUT_WORDS) &&
                (timeout_cycles < 1500000)
            )
            begin
                @(negedge clk);

                m_axis_tready =
                    ($urandom % 4) != 0;

                @(posedge clk);

                if (
                    m_axis_tvalid &&
                    m_axis_tready
                )
                begin
                    coefficient_index =
                        output_word % OUTPUT_WORDS_PER_PRODUCT;

                    if (m_axis_tkeep !== 4'hf)
                    begin
                        $display(
                            "FAIL TKEEP batch=%0d output=%0d value=%0b",
                            current_batch,
                            output_word,
                            m_axis_tkeep
                        );

                        $fatal(1);
                    end

                    if (
                        m_axis_tdata
                        !== expected[coefficient_index]
                    )
                    begin
                        $display(
                            "FAIL RESULT batch=%0d product=%0d coefficient=%0d result=%0d expected=%0d",
                            current_batch,
                            output_word / OUTPUT_WORDS_PER_PRODUCT,
                            coefficient_index,
                            m_axis_tdata,
                            expected[coefficient_index]
                        );

                        $fatal(1);
                    end

                    if (
                        (output_word == TOTAL_OUTPUT_WORDS - 1) &&
                        !m_axis_tlast
                    )
                    begin
                        $display(
                            "FAIL: final batch output lacks TLAST"
                        );

                        $fatal(1);
                    end

                    if (
                        (output_word != TOTAL_OUTPUT_WORDS - 1) &&
                        m_axis_tlast
                    )
                    begin
                        $display(
                            "FAIL: early output TLAST at word %0d",
                            output_word
                        );

                        $fatal(1);
                    end

                    output_word =
                        output_word + 1;
                end

                timeout_cycles =
                    timeout_cycles + 1;
            end

            m_axis_tready =
                1'b0;

            if (output_word != TOTAL_OUTPUT_WORDS)
            begin
                $display(
                    "TIMEOUT batch=%0d words=%0d busy=%0b",
                    current_batch,
                    output_word,
                    busy
                );

                $fatal(1);
            end

            $display(
                "PASS: received %0d-word result packet for batch %0d",
                TOTAL_OUTPUT_WORDS,
                current_batch
            );
        end
    endtask

    task automatic run_batch(
        input integer current_batch
    );
        begin
            if (
                s_axis_tready !== 1'b1 ||
                busy !== 1'b0
            )
            begin
                $display(
                    "FAIL: batch engine not ready before batch %0d",
                    current_batch
                );

                $fatal(1);
            end

            fork
                send_batch();
                receive_batch(current_batch);
            join

            repeat (3) @(posedge clk);

            if (protocol_error)
            begin
                $display(
                    "FAIL: protocol error after batch %0d",
                    current_batch
                );

                $fatal(1);
            end

            if (core_cycles !== EXPECTED_CORE_CYCLES)
            begin
                $display(
                    "FAIL CORE CYCLES batch=%0d result=%0d expected=%0d",
                    current_batch,
                    core_cycles,
                    EXPECTED_CORE_CYCLES
                );

                $fatal(1);
            end

            if (
                modular_multiplication_count
                !== 13'd4096
            )
            begin
                $display(
                    "FAIL MULTIPLICATION COUNT result=%0d expected=4096",
                    modular_multiplication_count
                );

                $fatal(1);
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../model/golden_n256/input_a.mem",
            input_a
        );

        $readmemh(
            "../model/golden_n256/input_b.mem",
            input_b
        );

        $readmemh(
            "../model/golden_n256/convolution.mem",
            expected
        );

        random_seed =
            32'h00c0ffee;

        seed_sink =
            $urandom(random_seed);

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        repeat (2) @(posedge clk);

        for (
            batch_number = 0;
            batch_number < BATCHES;
            batch_number = batch_number + 1
        )
        begin
            run_batch(batch_number);
        end

        if (
            completed_products
            !== BATCHES * BATCH_PRODUCTS
        )
        begin
            $display(
                "FAIL COMPLETED PRODUCTS result=%0d expected=%0d",
                completed_products,
                BATCHES * BATCH_PRODUCTS
            );

            $fatal(1);
        end

        $display(
            "PASS: %0d batches of %0d products",
            BATCHES,
            BATCH_PRODUCTS
        );

        $display(
            "PASS: %0d total polynomial products",
            BATCHES * BATCH_PRODUCTS
        );

        $display(
            "PASS: randomized input gaps and output backpressure"
        );

        $display(
            "PASS: TLAST occurs only at the end of each complete batch"
        );

        $display(
            "Input words per batch: %0d",
            TOTAL_INPUT_WORDS
        );

        $display(
            "Output words per batch: %0d",
            TOTAL_OUTPUT_WORDS
        );

        $display(
            "Core cycles per product: %0d",
            core_cycles
        );

        $finish;
    end

endmodule
