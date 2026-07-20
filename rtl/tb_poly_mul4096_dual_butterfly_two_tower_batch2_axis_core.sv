`timescale 1ns/1ps

module tb_poly_mul4096_dual_butterfly_two_tower_batch2_axis_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLES =
        4095;

    localparam integer BATCH_COUNT =
        2;

    localparam integer BATCH_INPUT_WORDS =
        2 + BATCH_COUNT * 2 * N;

    localparam integer BATCH_OUTPUT_WORDS =
        BATCH_COUNT * N;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h50524f46;

    localparam logic [31:0] COMMAND_BATCH =
        32'h4d554c42;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [31:0] Q1 =
        32'd1073668097;

`ifdef FAST_MODMUL

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd214018;

    localparam integer GLOBAL_WATCHDOG_CYCLES =
        1500000;

`else

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd631810;

    localparam integer GLOBAL_WATCHDOG_CYCLES =
        3200000;

`endif

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic [63:0] s_axis_tdata =
        64'd0;

    logic s_axis_tvalid =
        1'b0;

    logic s_axis_tready;

    logic s_axis_tlast =
        1'b0;

    logic [63:0] m_axis_tdata;
    logic m_axis_tvalid;

    logic m_axis_tready =
        1'b0;

    logic m_axis_tlast;

    logic protocol_error;
    logic profile_ready;

    logic [31:0] active_modulus_lane0;
    logic [31:0] active_modulus_lane1;

    logic [31:0] completed_profiles;
    logic [31:0] completed_products;
    logic [31:0] completed_batches;

    logic accelerator_busy;

    logic [31:0] core_cycles_lane0;
    logic [31:0] core_cycles_lane1;

    logic [16:0] modular_multiplications_lane0;
    logic [16:0] modular_multiplications_lane1;

    logic [31:0] profile0_twist [0:N-1];
    logic [31:0] profile1_twist [0:N-1];

    logic [31:0] profile0_forward [0:COMPACT_TWIDDLES-1];
    logic [31:0] profile1_forward [0:COMPACT_TWIDDLES-1];

    logic [31:0] profile0_inverse [0:COMPACT_TWIDDLES-1];
    logic [31:0] profile1_inverse [0:COMPACT_TWIDDLES-1];

    logic [31:0] profile0_scale [0:N-1];
    logic [31:0] profile1_scale [0:N-1];

    logic [31:0] product0_tower0_a [0:N-1];
    logic [31:0] product0_tower1_a [0:N-1];
    logic [31:0] product0_tower0_b [0:N-1];
    logic [31:0] product0_tower1_b [0:N-1];
    logic [31:0] product0_tower0_expected [0:N-1];
    logic [31:0] product0_tower1_expected [0:N-1];

    logic [31:0] product1_tower0_a [0:N-1];
    logic [31:0] product1_tower1_a [0:N-1];
    logic [31:0] product1_tower0_b [0:N-1];
    logic [31:0] product1_tower1_b [0:N-1];
    logic [31:0] product1_tower0_expected [0:N-1];
    logic [31:0] product1_tower1_expected [0:N-1];

    integer address;
    integer elapsed_cycles;
    integer random_seed;

    integer batch_input_handshakes;
    integer batch_output_handshakes;
    integer batch_input_tlast_handshakes;
    integer batch_output_tlast_handshakes;

    logic count_batch_traffic =
        1'b0;

    poly_mul4096_dual_butterfly_two_tower_batch_axis_core dut (
        .clk                           (clk),
        .reset_n                       (reset_n),

        .s_axis_tdata                  (s_axis_tdata),
        .s_axis_tvalid                 (s_axis_tvalid),
        .s_axis_tready                 (s_axis_tready),
        .s_axis_tlast                  (s_axis_tlast),

        .m_axis_tdata                  (m_axis_tdata),
        .m_axis_tvalid                 (m_axis_tvalid),
        .m_axis_tready                 (m_axis_tready),
        .m_axis_tlast                  (m_axis_tlast),

        .protocol_error                (protocol_error),
        .profile_ready                 (profile_ready),

        .active_modulus_lane0          (active_modulus_lane0),
        .active_modulus_lane1          (active_modulus_lane1),

        .completed_profiles            (completed_profiles),
        .completed_products            (completed_products),
        .completed_batches             (completed_batches),

        .accelerator_busy              (accelerator_busy),

        .core_cycles_lane0             (core_cycles_lane0),
        .core_cycles_lane1             (core_cycles_lane1),

        .modular_multiplications_lane0 (modular_multiplications_lane0),
        .modular_multiplications_lane1 (modular_multiplications_lane1)
    );

    always #5 clk = ~clk;

    task automatic send_pair(
        input logic [31:0] lane0_word,
        input logic [31:0] lane1_word,
        input logic        last
    );
        integer send_gap;

        begin
            send_gap =
                $urandom_range(0, 3);

            repeat (send_gap)
            begin
                @(negedge clk);

                s_axis_tvalid =
                    1'b0;

                s_axis_tlast =
                    1'b0;
            end

            @(negedge clk);

            s_axis_tdata = {
                lane1_word,
                lane0_word
            };

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

    task automatic send_dual_profile;
        begin
            send_pair(
                COMMAND_PROFILE,
                COMMAND_PROFILE,
                1'b0
            );

            send_pair(
                Q0,
                Q1,
                1'b0
            );

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_twist[address],
                    profile1_twist[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLES;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_forward[address],
                    profile1_forward[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLES;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_inverse[address],
                    profile1_inverse[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_scale[address],
                    profile1_scale[address],
                    address == N - 1
                );
            end
        end
    endtask

    task automatic send_dual_batch2;
        integer send_address;
        begin
            send_pair(
                COMMAND_BATCH,
                COMMAND_BATCH,
                1'b0
            );

            send_pair(
                BATCH_COUNT,
                BATCH_COUNT,
                1'b0
            );

            for (
                send_address = 0;
                send_address < N;
                send_address = send_address + 1
            )
            begin
                send_pair(
                    product0_tower0_a[send_address],
                    product0_tower1_a[send_address],
                    1'b0
                );
            end

            for (
                send_address = 0;
                send_address < N;
                send_address = send_address + 1
            )
            begin
                send_pair(
                    product0_tower0_b[send_address],
                    product0_tower1_b[send_address],
                    1'b0
                );
            end

            for (
                send_address = 0;
                send_address < N;
                send_address = send_address + 1
            )
            begin
                send_pair(
                    product1_tower0_a[send_address],
                    product1_tower1_a[send_address],
                    1'b0
                );
            end

            for (
                send_address = 0;
                send_address < N;
                send_address = send_address + 1
            )
            begin
                send_pair(
                    product1_tower0_b[send_address],
                    product1_tower1_b[send_address],
                    send_address == N - 1
                );
            end
        end
    endtask

    task automatic receive_dual_batch2;
        integer product_number;
        integer receive_address;
        integer receive_gap;

        logic [31:0] lane0_result;
        logic [31:0] lane1_result;
        logic [31:0] lane0_expected;
        logic [31:0] lane1_expected;
        logic expected_last;

        begin
            for (
                product_number = 0;
                product_number < BATCH_COUNT;
                product_number = product_number + 1
            )
            begin
                for (
                    receive_address = 0;
                    receive_address < N;
                    receive_address = receive_address + 1
                )
                begin
                    receive_gap =
                        $urandom_range(0, 5);

                    repeat (receive_gap)
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

                    lane0_result =
                        m_axis_tdata[31:0];

                    lane1_result =
                        m_axis_tdata[63:32];

                    if (product_number == 0)
                    begin
                        lane0_expected =
                            product0_tower0_expected[receive_address];

                        lane1_expected =
                            product0_tower1_expected[receive_address];
                    end
                    else
                    begin
                        lane0_expected =
                            product1_tower0_expected[receive_address];

                        lane1_expected =
                            product1_tower1_expected[receive_address];
                    end

                    if (lane0_result !== lane0_expected)
                    begin
                        $display(
                            "FAIL TOWER0 product=%0d receive_address=%0d result=%0d expected=%0d",
                            product_number,
                            receive_address,
                            lane0_result,
                            lane0_expected
                        );

                        $fatal(1);
                    end

                    if (lane1_result !== lane1_expected)
                    begin
                        $display(
                            "FAIL TOWER1 product=%0d receive_address=%0d result=%0d expected=%0d",
                            product_number,
                            receive_address,
                            lane1_result,
                            lane1_expected
                        );

                        $fatal(1);
                    end

                    expected_last =
                        product_number == BATCH_COUNT - 1
                        && receive_address == N - 1;

                    if (m_axis_tlast !== expected_last)
                    begin
                        $display(
                            "FAIL TLAST product=%0d receive_address=%0d result=%0d expected=%0d",
                            product_number,
                            receive_address,
                            m_axis_tlast,
                            expected_last
                        );

                        $fatal(1);
                    end

                    @(negedge clk);

                    m_axis_tready =
                        1'b0;
                end
            end
        end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            elapsed_cycles <=
                0;

            batch_input_handshakes <=
                0;

            batch_output_handshakes <=
                0;

            batch_input_tlast_handshakes <=
                0;

            batch_output_tlast_handshakes <=
                0;
        end
        else
        begin
            elapsed_cycles <=
                elapsed_cycles + 1;

            if (count_batch_traffic)
            begin
                if (s_axis_tvalid && s_axis_tready)
                begin
                    batch_input_handshakes <=
                        batch_input_handshakes + 1;

                    if (s_axis_tlast)
                    begin
                        batch_input_tlast_handshakes <=
                            batch_input_tlast_handshakes + 1;
                    end
                end

                if (m_axis_tvalid && m_axis_tready)
                begin
                    batch_output_handshakes <=
                        batch_output_handshakes + 1;

                    if (m_axis_tlast)
                    begin
                        batch_output_tlast_handshakes <=
                            batch_output_tlast_handshakes + 1;
                    end
                end
            end

            if (
                elapsed_cycles != 0
                && elapsed_cycles % 100000 == 0
            )
            begin
                $display(
                    "PROGRESS BATCH2 elapsed=%0d profiles=%0d products=%0d batches=%0d busy=%0d input_words=%0d output_words=%0d",
                    elapsed_cycles,
                    completed_profiles,
                    completed_products,
                    completed_batches,
                    accelerator_busy,
                    batch_input_handshakes,
                    batch_output_handshakes
                );
            end

            if (elapsed_cycles > GLOBAL_WATCHDOG_CYCLES)
            begin
                $display(
                    "FAIL BATCH2 WATCHDOG elapsed=%0d profiles=%0d products=%0d batches=%0d busy=%0d protocol_error=%0d lane0_cycles=%0d lane1_cycles=%0d",
                    elapsed_cycles,
                    completed_profiles,
                    completed_products,
                    completed_batches,
                    accelerator_busy,
                    protocol_error,
                    core_cycles_lane0,
                    core_cycles_lane1
                );

                $fatal(1);
            end
        end
    end

    initial
    begin
        random_seed =
            32'h2f409627;

        random_seed =
            $urandom(random_seed);

        $display(
            "START: loading two distinct OpenFHE batch vectors"
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile0/twist_factors.mem",
            profile0_twist
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile1/twist_factors.mem",
            profile1_twist
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile0/forward_twiddles.mem",
            profile0_forward
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile1/forward_twiddles.mem",
            profile1_forward
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile0/inverse_twiddles.mem",
            profile0_inverse
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile1/inverse_twiddles.mem",
            profile1_inverse
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile0/inverse_scale_factors.mem",
            profile0_scale
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0/profile1/inverse_scale_factors.mem",
            profile1_scale
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0_tower0_a.mem",
            product0_tower0_a
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0_tower1_a.mem",
            product0_tower1_a
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0_tower0_b.mem",
            product0_tower0_b
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0_tower1_b.mem",
            product0_tower1_b
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0_tower0_expected.mem",
            product0_tower0_expected
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product0_tower1_expected.mem",
            product0_tower1_expected
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product1_tower0_a.mem",
            product1_tower0_a
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product1_tower1_a.mem",
            product1_tower1_a
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product1_tower0_b.mem",
            product1_tower0_b
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product1_tower1_b.mem",
            product1_tower1_b
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product1_tower0_expected.mem",
            product1_tower0_expected
        );

        $readmemh(
            "generated_dual_butterfly_batch2/product1_tower1_expected.mem",
            product1_tower1_expected
        );

        $display(
            "PASS: loaded two distinct OpenFHE batch products"
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        $display(
            "START: streaming paired q0/q1 runtime profile"
        );

        send_dual_profile();

        while (!profile_ready)
        begin
            @(posedge clk);
        end

        if (protocol_error)
        begin
            $display(
                "FAIL: protocol error after dual profile"
            );

            $fatal(1);
        end

        if (
            active_modulus_lane0 !== Q0
            || active_modulus_lane1 !== Q1
        )
        begin
            $display(
                "FAIL MODULI lane0=%0d lane1=%0d",
                active_modulus_lane0,
                active_modulus_lane1
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

        $display(
            "PASS: loaded q0 and q1 profiles once"
        );

        batch_input_handshakes =
            0;

        batch_output_handshakes =
            0;

        batch_input_tlast_handshakes =
            0;

        batch_output_tlast_handshakes =
            0;

        count_batch_traffic =
            1'b1;

        $display(
            "START: one batch-of-two AXI input and output transaction"
        );

        fork
            begin
                send_dual_batch2();
            end

            begin
                receive_dual_batch2();
            end
        join

        @(negedge clk);

        count_batch_traffic =
            1'b0;

        if (protocol_error)
        begin
            $display(
                "FAIL: protocol error after batch-of-two"
            );

            $fatal(1);
        end

        if (completed_products !== 32'd2)
        begin
            $display(
                "FAIL PRODUCT COUNT result=%0d expected=2",
                completed_products
            );

            $fatal(1);
        end

        if (completed_batches !== 32'd1)
        begin
            $display(
                "FAIL BATCH COUNT result=%0d expected=1",
                completed_batches
            );

            $fatal(1);
        end

        if (batch_input_handshakes !== BATCH_INPUT_WORDS)
        begin
            $display(
                "FAIL INPUT WORDS result=%0d expected=%0d",
                batch_input_handshakes,
                BATCH_INPUT_WORDS
            );

            $fatal(1);
        end

        if (batch_output_handshakes !== BATCH_OUTPUT_WORDS)
        begin
            $display(
                "FAIL OUTPUT WORDS result=%0d expected=%0d",
                batch_output_handshakes,
                BATCH_OUTPUT_WORDS
            );

            $fatal(1);
        end

        if (batch_input_tlast_handshakes !== 1)
        begin
            $display(
                "FAIL INPUT TLAST COUNT result=%0d expected=1",
                batch_input_tlast_handshakes
            );

            $fatal(1);
        end

        if (batch_output_tlast_handshakes !== 1)
        begin
            $display(
                "FAIL OUTPUT TLAST COUNT result=%0d expected=1",
                batch_output_tlast_handshakes
            );

            $fatal(1);
        end

        if (
            core_cycles_lane0 !== EXPECTED_CYCLES
            || core_cycles_lane1 !== EXPECTED_CYCLES
        )
        begin
            $display(
                "FAIL CYCLES lane0=%0d lane1=%0d expected=%0d",
                core_cycles_lane0,
                core_cycles_lane1,
                EXPECTED_CYCLES
            );

            $fatal(1);
        end

        if (
            modular_multiplications_lane0 !== 17'd90112
            || modular_multiplications_lane1 !== 17'd90112
        )
        begin
            $display(
                "FAIL MULTIPLICATIONS lane0=%0d lane1=%0d",
                modular_multiplications_lane0,
                modular_multiplications_lane1
            );

            $fatal(1);
        end

        $display(
            "PASS: one MULB input frame contained two distinct products"
        );

        $display(
            "PASS: both q0/q1 products exactly equal OpenFHE"
        );

        $display(
            "PASS: both products returned in one output frame"
        );

        $display(
            "PASS: exactly one input TLAST and one output TLAST"
        );

        $display(
            "PASS: randomized input gaps and output backpressure"
        );

        $display(
            "PASS: one runtime profile supported the complete batch"
        );

        $display(
            "Batch input words: %0d",
            BATCH_INPUT_WORDS
        );

        $display(
            "Batch input bytes: %0d",
            BATCH_INPUT_WORDS * 8
        );

        $display(
            "Batch output words: %0d",
            BATCH_OUTPUT_WORDS
        );

        $display(
            "Batch output bytes: %0d",
            BATCH_OUTPUT_WORDS * 8
        );

        $display(
            "Per-product core cycles: %0d",
            core_cycles_lane0
        );

        $finish;
    end

endmodule
