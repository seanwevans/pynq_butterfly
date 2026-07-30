`timescale 1ns/1ps

module tb_poly_mul4096_axis_core;

    localparam integer N =
        4096;

    localparam integer INPUT_WORDS =
        8192;

    localparam integer OUTPUT_WORDS =
        4096;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic [31:0] s_axis_tdata =
        32'd0;

    logic s_axis_tvalid =
        1'b0;

    logic s_axis_tready;

    logic s_axis_tlast =
        1'b0;

    logic [31:0] m_axis_tdata;
    logic m_axis_tvalid;

    logic m_axis_tready =
        1'b0;

    logic m_axis_tlast;

    logic protocol_error;
    logic [31:0] completed_products;
    logic [31:0] core_cycles;
    logic [16:0] modular_multiplications;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];
    logic [31:0] expected_convolution [0:N-1];

    logic hold_active =
        1'b0;

    logic [31:0] held_data =
        32'd0;

    logic held_last =
        1'b0;

    integer word_index;
    integer output_index;
    integer product_index;
    integer gap_cycles;
    integer random_seed;
    integer seed_sink;

    poly_mul4096_axis_core dut (
        .clk                     (clk),
        .reset_n                 (reset_n),

        .s_axis_tdata            (s_axis_tdata),
        .s_axis_tvalid           (s_axis_tvalid),
        .s_axis_tready           (s_axis_tready),
        .s_axis_tlast            (s_axis_tlast),

        .m_axis_tdata            (m_axis_tdata),
        .m_axis_tvalid           (m_axis_tvalid),
        .m_axis_tready           (m_axis_tready),
        .m_axis_tlast            (m_axis_tlast),

        .protocol_error          (protocol_error),
        .completed_products      (completed_products),
        .core_cycles             (core_cycles),
        .modular_multiplications (modular_multiplications)
    );

    always #5 clk = ~clk;

    /*
     * AXI4-Stream requires all output payload signals to remain stable
     * while TVALID is asserted and TREADY is low.
     */
    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            hold_active <=
                1'b0;

            held_data <=
                32'd0;

            held_last <=
                1'b0;
        end
        else
        begin
            if (hold_active)
            begin
                if (
                    !m_axis_tvalid
                    || m_axis_tdata !== held_data
                    || m_axis_tlast !== held_last
                )
                begin
                    $display(
                        "FAIL: AXI output changed under backpressure"
                    );

                    $fatal(1);
                end

                if (m_axis_tready)
                begin
                    hold_active <=
                        1'b0;
                end
            end
            else if (
                m_axis_tvalid
                && !m_axis_tready
            )
            begin
                hold_active <=
                    1'b1;

                held_data <=
                    m_axis_tdata;

                held_last <=
                    m_axis_tlast;
            end
        end
    end

    task automatic stream_input_frame;
        begin
            for (
                word_index = 0;
                word_index < INPUT_WORDS;
                word_index = word_index + 1
            )
            begin
                gap_cycles =
                    $urandom % 4;

                repeat (gap_cycles)
                begin
                    @(negedge clk);

                    s_axis_tvalid =
                        1'b0;

                    s_axis_tlast =
                        1'b0;
                end

                @(negedge clk);

                s_axis_tvalid =
                    1'b1;

                if (word_index < N)
                begin
                    s_axis_tdata =
                        input_a[word_index];
                end
                else
                begin
                    s_axis_tdata =
                        input_b[word_index - N];
                end

                s_axis_tlast =
                    word_index == INPUT_WORDS - 1;

                while (!s_axis_tready)
                begin
                    @(posedge clk);
                    @(negedge clk);
                end

                @(posedge clk);
            end

            @(negedge clk);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;

            $display(
                "PASS: streamed 8192-word A||B input frame"
            );
        end
    endtask

    task automatic receive_output_frame(
        input integer requested_product
    );
        begin
            output_index =
                0;

            while (output_index < OUTPUT_WORDS)
            begin
                @(negedge clk);

                m_axis_tready =
                    ($urandom % 5) != 0;

                @(posedge clk);

                if (
                    m_axis_tvalid
                    && m_axis_tready
                )
                begin
                    if (
                        m_axis_tdata
                        !== expected_convolution[output_index]
                    )
                    begin
                        $display(
                            "FAIL OUTPUT product=%0d address=%0d result=%0d expected=%0d",
                            requested_product,
                            output_index,
                            m_axis_tdata,
                            expected_convolution[output_index]
                        );

                        $fatal(1);
                    end

                    if (
                        m_axis_tlast
                        !== (output_index == OUTPUT_WORDS - 1)
                    )
                    begin
                        $display(
                            "FAIL TLAST product=%0d address=%0d result=%0b expected=%0b",
                            requested_product,
                            output_index,
                            m_axis_tlast,
                            output_index == OUTPUT_WORDS - 1
                        );

                        $fatal(1);
                    end

                    output_index =
                        output_index + 1;
                end
            end

            @(negedge clk);

            m_axis_tready =
                1'b0;

            $display(
                "PASS: received 4096-word result frame %0d with correct TLAST",
                requested_product
            );
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

        random_seed =
            32'h4096a715;

        seed_sink =
            $urandom(random_seed);

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        for (
            product_index = 0;
            product_index < 2;
            product_index = product_index + 1
        )
        begin
            stream_input_frame();
            receive_output_frame(product_index);

            if (protocol_error)
            begin
                $display(
                    "FAIL: protocol_error asserted for valid frame"
                );

                $fatal(1);
            end

            if (core_cycles != 32'd1376268)
            begin
                $display(
                    "FAIL CORE CYCLES product=%0d result=%0d expected=1376268",
                    product_index,
                    core_cycles
                );

                $fatal(1);
            end

            if (
                modular_multiplications
                != 17'd90112
            )
            begin
                $display(
                    "FAIL MULTIPLICATION COUNT product=%0d result=%0d expected=90112",
                    product_index,
                    modular_multiplications
                );

                $fatal(1);
            end
        end

        if (completed_products != 32'd2)
        begin
            $display(
                "FAIL COMPLETED PRODUCTS result=%0d expected=2",
                completed_products
            );

            $fatal(1);
        end

        $display(
            "PASS: two back-to-back streamed N=4096 polynomial products"
        );

        $display(
            "PASS: randomized input gaps and output backpressure"
        );

        $display(
            "Input frame words: 8192"
        );

        $display(
            "Input frame bytes: 32768"
        );

        $display(
            "Output frame words: 4096"
        );

        $display(
            "Output frame bytes: 16384"
        );

        $display(
            "Constant core cycles: %0d",
            core_cycles
        );

        $finish;
    end

endmodule
