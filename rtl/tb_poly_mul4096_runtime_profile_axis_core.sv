`timescale 1ns/1ps

module tb_poly_mul4096_runtime_profile_axis_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLE_WORDS =
        4095;

    localparam integer PROFILE_PAYLOAD_WORDS =
        16382;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h50524f46;

    localparam logic [31:0] COMMAND_PRODUCT =
        32'h4d554c31;

    localparam logic [31:0] PROFILE_MODULUS =
        32'd1073692673;

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd1339394;

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
    logic profile_ready;
    logic [31:0] active_modulus;

    logic [31:0] completed_profiles;
    logic [31:0] completed_products;

    logic [31:0] profile_words_received;
    logic [31:0] product_words_received;

    logic accelerator_busy;
    logic [31:0] core_cycles;
    logic [16:0] modular_multiplications;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];
    logic [31:0] expected_convolution [0:N-1];

    logic [31:0] twist_factors [0:N-1];
    logic [31:0] forward_twiddles [0:COMPACT_TWIDDLE_WORDS-1];
    logic [31:0] inverse_twiddles [0:COMPACT_TWIDDLE_WORDS-1];
    logic [31:0] inverse_scale_factors [0:N-1];

    integer address;
    integer run_index;
    integer gap_cycles;
    integer random_seed;

    logic [31:0] first_cycles;

    poly_mul4096_runtime_profile_axis_core dut (
        .clk                       (clk),
        .reset_n                   (reset_n),

        .s_axis_tdata              (s_axis_tdata),
        .s_axis_tvalid             (s_axis_tvalid),
        .s_axis_tready             (s_axis_tready),
        .s_axis_tlast              (s_axis_tlast),

        .m_axis_tdata              (m_axis_tdata),
        .m_axis_tvalid             (m_axis_tvalid),
        .m_axis_tready             (m_axis_tready),
        .m_axis_tlast              (m_axis_tlast),

        .protocol_error            (protocol_error),
        .profile_ready             (profile_ready),
        .active_modulus            (active_modulus),

        .completed_profiles        (completed_profiles),
        .completed_products        (completed_products),

        .profile_words_received    (profile_words_received),
        .product_words_received    (product_words_received),

        .accelerator_busy          (accelerator_busy),
        .core_cycles               (core_cycles),
        .modular_multiplications   (modular_multiplications)
    );

    always #5 clk = ~clk;

    task automatic send_word(
        input logic [31:0] data,
        input logic        last
    );
        begin
            gap_cycles =
                $urandom_range(0, 3);

            repeat (gap_cycles)
            begin
                @(negedge clk);

                s_axis_tvalid =
                    1'b0;

                s_axis_tlast =
                    1'b0;
            end

            @(negedge clk);

            s_axis_tdata =
                data;

            s_axis_tvalid =
                1'b1;

            s_axis_tlast =
                last;

            @(posedge clk);

            while (!s_axis_tready)
            begin
                @(posedge clk);
            end

            @(negedge clk);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;
        end
    endtask

    task automatic send_profile_frame;
        begin
            send_word(
                COMMAND_PROFILE,
                1'b0
            );

            send_word(
                PROFILE_MODULUS,
                1'b0
            );

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_word(
                    twist_factors[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLE_WORDS;
                address = address + 1
            )
            begin
                send_word(
                    forward_twiddles[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLE_WORDS;
                address = address + 1
            )
            begin
                send_word(
                    inverse_twiddles[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_word(
                    inverse_scale_factors[address],
                    address == N - 1
                );
            end
        end
    endtask

    task automatic send_product_frame;
        begin
            send_word(
                COMMAND_PRODUCT,
                1'b0
            );

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_word(
                    input_a[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_word(
                    input_b[address],
                    address == N - 1
                );
            end
        end
    endtask

    task automatic receive_and_compare_product;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                gap_cycles =
                    $urandom_range(0, 5);

                repeat (gap_cycles)
                begin
                    @(negedge clk);

                    m_axis_tready =
                        1'b0;
                end

                @(negedge clk);

                m_axis_tready =
                    1'b1;

                @(posedge clk);

                while (!m_axis_tvalid)
                begin
                    @(posedge clk);
                end

                if (
                    m_axis_tdata
                    !== expected_convolution[address]
                )
                begin
                    $display(
                        "FAIL OUTPUT address=%0d result=%0d expected=%0d",
                        address,
                        m_axis_tdata,
                        expected_convolution[address]
                    );

                    $fatal(1);
                end

                if (
                    m_axis_tlast
                    !== (address == N - 1)
                )
                begin
                    $display(
                        "FAIL OUTPUT TLAST address=%0d result=%0d expected=%0d",
                        address,
                        m_axis_tlast,
                        address == N - 1
                    );

                    $fatal(1);
                end

                @(negedge clk);

                m_axis_tready =
                    1'b0;
            end
        end
    endtask

    initial
    begin
        random_seed =
            32'h4096a511;

        random_seed =
            $urandom(random_seed);

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

        $readmemh(
            "../tests/fixtures/ntt_n4096/twist_factors.mem",
            twist_factors
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_twiddles.mem",
            forward_twiddles
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_twiddles.mem",
            inverse_twiddles
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_scale_factors.mem",
            inverse_scale_factors
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        send_profile_frame();

        while (!profile_ready)
        begin
            @(posedge clk);
        end

        if (protocol_error)
        begin
            $display(
                "FAIL: protocol error after valid profile frame"
            );

            $fatal(1);
        end

        if (completed_profiles !== 32'd1)
        begin
            $display(
                "FAIL PROFILE COUNT result=%0d expected=1",
                completed_profiles
            );

            $fatal(1);
        end

        if (
            profile_words_received
            !== PROFILE_PAYLOAD_WORDS
        )
        begin
            $display(
                "FAIL PROFILE WORDS result=%0d expected=%0d",
                profile_words_received,
                PROFILE_PAYLOAD_WORDS
            );

            $fatal(1);
        end

        if (active_modulus !== PROFILE_MODULUS)
        begin
            $display(
                "FAIL MODULUS result=%0d expected=%0d",
                active_modulus,
                PROFILE_MODULUS
            );

            $fatal(1);
        end

        $display(
            "PASS: streamed 65536-byte runtime profile frame"
        );

        for (
            run_index = 0;
            run_index < 2;
            run_index = run_index + 1
        )
        begin
            send_product_frame();
            receive_and_compare_product();

            if (protocol_error)
            begin
                $display(
                    "FAIL: protocol error after valid product frame"
                );

                $fatal(1);
            end

            if (
                product_words_received
                !== 32'd8192
            )
            begin
                $display(
                    "FAIL PRODUCT WORDS result=%0d expected=8192",
                    product_words_received
                );

                $fatal(1);
            end

            if (
                completed_products
                !== run_index + 1
            )
            begin
                $display(
                    "FAIL PRODUCT COUNT result=%0d expected=%0d",
                    completed_products,
                    run_index + 1
                );

                $fatal(1);
            end

            if (core_cycles !== EXPECTED_CYCLES)
            begin
                $display(
                    "FAIL CYCLES result=%0d expected=%0d",
                    core_cycles,
                    EXPECTED_CYCLES
                );

                $fatal(1);
            end

            if (
                modular_multiplications
                !== 17'd90112
            )
            begin
                $display(
                    "FAIL MULTIPLICATION COUNT result=%0d expected=90112",
                    modular_multiplications
                );

                $fatal(1);
            end

            if (run_index == 0)
            begin
                first_cycles =
                    core_cycles;
            end
            else if (core_cycles !== first_cycles)
            begin
                $display(
                    "FAIL CONSTANT TIME first=%0d second=%0d",
                    first_cycles,
                    core_cycles
                );

                $fatal(1);
            end

            $display(
                "PASS: streamed runtime-profile product run %0d",
                run_index
            );
        end

        $display(
            "PASS: one streamed profile supports repeated products"
        );

        $display(
            "PASS: randomized input gaps and output backpressure"
        );

        $display(
            "PASS: runtime command framing preserves exact q0 product"
        );

        $display(
            "Profile frame words: 16384"
        );

        $display(
            "Profile frame bytes: 65536"
        );

        $display(
            "Product input frame words: 8193"
        );

        $display(
            "Product input frame bytes: 32772"
        );

        $display(
            "Product output frame words: 4096"
        );

        $display(
            "Product output frame bytes: 16384"
        );

        $display(
            "Constant core cycles: %0d",
            first_cycles
        );

        $finish;
    end

endmodule
