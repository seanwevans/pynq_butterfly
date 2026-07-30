`timescale 1ns/1ps

module tb_poly_mul4096_dual_butterfly_two_tower_prefetch4_axis_core;

    localparam integer N = 4096;
    localparam integer COMPACT_TWIDDLES = 4095;
    localparam integer BATCH_COUNT = 4;
    localparam integer BATCH_INPUT_WORDS = 2 + BATCH_COUNT * 2 * N;
    localparam integer BATCH_OUTPUT_WORDS = BATCH_COUNT * N;

    localparam logic [31:0] COMMAND_PROFILE = 32'h50524f46;
    localparam logic [31:0] COMMAND_BATCH = 32'h4d554c42;
    localparam logic [31:0] Q0 = 32'd1073692673;
    localparam logic [31:0] Q1 = 32'd1073668097;

`ifdef FAST_MODMUL
    localparam logic [31:0] EXPECTED_CYCLES = 32'd214018;
    localparam integer GLOBAL_WATCHDOG_CYCLES = 2500000;
`else
    localparam logic [31:0] EXPECTED_CYCLES = 32'd631810;
    localparam integer GLOBAL_WATCHDOG_CYCLES = 5000000;
`endif

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [63:0] s_axis_tdata = 64'd0;
    logic s_axis_tvalid = 1'b0;
    logic s_axis_tready;
    logic s_axis_tlast = 1'b0;
    logic [63:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tready = 1'b0;
    logic m_axis_tlast;

    logic protocol_error;
    logic profile_ready;
    logic [31:0] active_modulus_lane0;
    logic [31:0] active_modulus_lane1;
    logic [31:0] completed_profiles;
    logic [31:0] completed_products;
    logic [31:0] completed_batches;
    logic [31:0] completed_prefetches;
    logic [31:0] completed_refills;
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
    logic [31:0] product0_tower0_b [0:N-1];
    logic [31:0] product0_tower0_expected [0:N-1];
    logic [31:0] product0_tower1_a [0:N-1];
    logic [31:0] product0_tower1_b [0:N-1];
    logic [31:0] product0_tower1_expected [0:N-1];
    logic [31:0] product1_tower0_a [0:N-1];
    logic [31:0] product1_tower0_b [0:N-1];
    logic [31:0] product1_tower0_expected [0:N-1];
    logic [31:0] product1_tower1_a [0:N-1];
    logic [31:0] product1_tower1_b [0:N-1];
    logic [31:0] product1_tower1_expected [0:N-1];
    logic [31:0] product2_tower0_a [0:N-1];
    logic [31:0] product2_tower0_b [0:N-1];
    logic [31:0] product2_tower0_expected [0:N-1];
    logic [31:0] product2_tower1_a [0:N-1];
    logic [31:0] product2_tower1_b [0:N-1];
    logic [31:0] product2_tower1_expected [0:N-1];
    logic [31:0] product3_tower0_a [0:N-1];
    logic [31:0] product3_tower0_b [0:N-1];
    logic [31:0] product3_tower0_expected [0:N-1];
    logic [31:0] product3_tower1_a [0:N-1];
    logic [31:0] product3_tower1_b [0:N-1];
    logic [31:0] product3_tower1_expected [0:N-1];

    integer elapsed_cycles;
    integer random_seed;
    integer batch_input_handshakes;
    integer batch_output_handshakes;
    integer batch_input_tlast_handshakes;
    integer batch_output_tlast_handshakes;
    integer input_words_at_first_output;
    logic first_output_seen;
    logic count_batch_traffic = 1'b0;

    function automatic [31:0] tower0_a_value;
        input integer product_number;
        input integer address;

        begin
            case (product_number)
            0: tower0_a_value = product0_tower0_a[address];
            1: tower0_a_value = product1_tower0_a[address];
            2: tower0_a_value = product2_tower0_a[address];
            3: tower0_a_value = product3_tower0_a[address];
                default: tower0_a_value = 32'd0;
            endcase
        end
    endfunction

    function automatic [31:0] tower1_a_value;
        input integer product_number;
        input integer address;

        begin
            case (product_number)
            0: tower1_a_value = product0_tower1_a[address];
            1: tower1_a_value = product1_tower1_a[address];
            2: tower1_a_value = product2_tower1_a[address];
            3: tower1_a_value = product3_tower1_a[address];
                default: tower1_a_value = 32'd0;
            endcase
        end
    endfunction

    function automatic [31:0] tower0_b_value;
        input integer product_number;
        input integer address;

        begin
            case (product_number)
            0: tower0_b_value = product0_tower0_b[address];
            1: tower0_b_value = product1_tower0_b[address];
            2: tower0_b_value = product2_tower0_b[address];
            3: tower0_b_value = product3_tower0_b[address];
                default: tower0_b_value = 32'd0;
            endcase
        end
    endfunction

    function automatic [31:0] tower1_b_value;
        input integer product_number;
        input integer address;

        begin
            case (product_number)
            0: tower1_b_value = product0_tower1_b[address];
            1: tower1_b_value = product1_tower1_b[address];
            2: tower1_b_value = product2_tower1_b[address];
            3: tower1_b_value = product3_tower1_b[address];
                default: tower1_b_value = 32'd0;
            endcase
        end
    endfunction

    function automatic [31:0] tower0_expected_value;
        input integer product_number;
        input integer address;

        begin
            case (product_number)
            0: tower0_expected_value = product0_tower0_expected[address];
            1: tower0_expected_value = product1_tower0_expected[address];
            2: tower0_expected_value = product2_tower0_expected[address];
            3: tower0_expected_value = product3_tower0_expected[address];
                default: tower0_expected_value = 32'd0;
            endcase
        end
    endfunction

    function automatic [31:0] tower1_expected_value;
        input integer product_number;
        input integer address;

        begin
            case (product_number)
            0: tower1_expected_value = product0_tower1_expected[address];
            1: tower1_expected_value = product1_tower1_expected[address];
            2: tower1_expected_value = product2_tower1_expected[address];
            3: tower1_expected_value = product3_tower1_expected[address];
                default: tower1_expected_value = 32'd0;
            endcase
        end
    endfunction


    poly_mul4096_dual_butterfly_two_tower_prefetch_axis_core dut (
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
        .completed_prefetches          (completed_prefetches),
        .completed_refills             (completed_refills),
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
        input logic last
    );
        integer send_gap;
        begin
            send_gap = $urandom_range(0, 3);

            repeat (send_gap)
            begin
                @(negedge clk);
                s_axis_tvalid = 1'b0;
                s_axis_tlast = 1'b0;
            end

            @(negedge clk);
            s_axis_tdata = {lane1_word, lane0_word};
            s_axis_tvalid = 1'b1;
            s_axis_tlast = last;

            @(posedge clk);
            while (!s_axis_tready)
            begin
                @(posedge clk);
            end

            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task automatic send_dual_profile;
        integer address;
        begin
            send_pair(COMMAND_PROFILE, COMMAND_PROFILE, 1'b0);
            send_pair(Q0, Q1, 1'b0);

            for (address = 0; address < N; address = address + 1)
                send_pair(profile0_twist[address], profile1_twist[address], 1'b0);

            for (address = 0; address < COMPACT_TWIDDLES; address = address + 1)
                send_pair(profile0_forward[address], profile1_forward[address], 1'b0);

            for (address = 0; address < COMPACT_TWIDDLES; address = address + 1)
                send_pair(profile0_inverse[address], profile1_inverse[address], 1'b0);

            for (address = 0; address < N; address = address + 1)
                send_pair(profile0_scale[address], profile1_scale[address], address == N - 1);
        end
    endtask

    task automatic send_prefetch_batch4;
        integer product_number;
        integer address;
        begin
            send_pair(COMMAND_BATCH, COMMAND_BATCH, 1'b0);
            send_pair(BATCH_COUNT, BATCH_COUNT, 1'b0);

            for (product_number = 0; product_number < BATCH_COUNT; product_number = product_number + 1)
            begin
                for (address = 0; address < N; address = address + 1)
                    send_pair(
                        tower0_a_value(product_number, address),
                        tower1_a_value(product_number, address),
                        1'b0
                    );

                for (address = 0; address < N; address = address + 1)
                    send_pair(
                        tower0_b_value(product_number, address),
                        tower1_b_value(product_number, address),
                        product_number == BATCH_COUNT - 1 && address == N - 1
                    );
            end
        end
    endtask

    task automatic receive_prefetch_batch4;
        integer product_number;
        integer address;
        integer receive_gap;
        logic [31:0] lane0_result;
        logic [31:0] lane1_result;
        logic expected_last;
        begin
            for (product_number = 0; product_number < BATCH_COUNT; product_number = product_number + 1)
            begin
                for (address = 0; address < N; address = address + 1)
                begin
                    receive_gap = $urandom_range(0, 5);

                    repeat (receive_gap)
                    begin
                        @(negedge clk);
                        m_axis_tready = 1'b0;
                    end

                    @(negedge clk);
                    m_axis_tready = 1'b1;

                    @(posedge clk);
                    while (!m_axis_tvalid)
                    begin
                        @(posedge clk);
                    end

                    lane0_result = m_axis_tdata[31:0];
                    lane1_result = m_axis_tdata[63:32];

                    if (lane0_result !== tower0_expected_value(product_number, address))
                    begin
                        $display(
                            "FAIL TOWER0 product=%0d address=%0d result=%0d expected=%0d",
                            product_number,
                            address,
                            lane0_result,
                            tower0_expected_value(product_number, address)
                        );
                        $fatal(1);
                    end

                    if (lane1_result !== tower1_expected_value(product_number, address))
                    begin
                        $display(
                            "FAIL TOWER1 product=%0d address=%0d result=%0d expected=%0d",
                            product_number,
                            address,
                            lane1_result,
                            tower1_expected_value(product_number, address)
                        );
                        $fatal(1);
                    end

                    expected_last =
                        product_number == BATCH_COUNT - 1
                        && address == N - 1;

                    if (m_axis_tlast !== expected_last)
                    begin
                        $display(
                            "FAIL TLAST product=%0d address=%0d result=%0d expected=%0d",
                            product_number,
                            address,
                            m_axis_tlast,
                            expected_last
                        );
                        $fatal(1);
                    end

                    @(negedge clk);
                    m_axis_tready = 1'b0;
                end
            end
        end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            elapsed_cycles <= 0;
            batch_input_handshakes <= 0;
            batch_output_handshakes <= 0;
            batch_input_tlast_handshakes <= 0;
            batch_output_tlast_handshakes <= 0;
            input_words_at_first_output <= 0;
            first_output_seen <= 1'b0;
        end
        else
        begin
            elapsed_cycles <= elapsed_cycles + 1;

            if (count_batch_traffic)
            begin
                if (s_axis_tvalid && s_axis_tready)
                begin
                    batch_input_handshakes <= batch_input_handshakes + 1;
                    if (s_axis_tlast)
                        batch_input_tlast_handshakes <= batch_input_tlast_handshakes + 1;
                end

                if (m_axis_tvalid && m_axis_tready)
                begin
                    batch_output_handshakes <= batch_output_handshakes + 1;

                    if (!first_output_seen)
                    begin
                        first_output_seen <= 1'b1;
                        input_words_at_first_output <= batch_input_handshakes;
                    end

                    if (m_axis_tlast)
                        batch_output_tlast_handshakes <= batch_output_tlast_handshakes + 1;
                end
            end

            if (elapsed_cycles != 0 && elapsed_cycles % 100000 == 0)
            begin
                $display(
                    "PROGRESS PREFETCH4 elapsed=%0d products=%0d prefetches=%0d refills=%0d input=%0d output=%0d",
                    elapsed_cycles,
                    completed_products,
                    completed_prefetches,
                    completed_refills,
                    batch_input_handshakes,
                    batch_output_handshakes
                );
            end

            if (elapsed_cycles > GLOBAL_WATCHDOG_CYCLES)
            begin
                $display(
                    "FAIL PREFETCH4 WATCHDOG elapsed=%0d products=%0d prefetches=%0d refills=%0d protocol_error=%0d",
                    elapsed_cycles,
                    completed_products,
                    completed_prefetches,
                    completed_refills,
                    protocol_error
                );
                $fatal(1);
            end
        end
    end

    initial
    begin
        random_seed = 32'h6e504634;
        random_seed = $urandom(random_seed);

        $readmemh("generated_dual_butterfly_prefetch4/profile0/twist_factors.mem", profile0_twist);
        $readmemh("generated_dual_butterfly_prefetch4/profile1/twist_factors.mem", profile1_twist);
        $readmemh("generated_dual_butterfly_prefetch4/profile0/forward_twiddles.mem", profile0_forward);
        $readmemh("generated_dual_butterfly_prefetch4/profile1/forward_twiddles.mem", profile1_forward);
        $readmemh("generated_dual_butterfly_prefetch4/profile0/inverse_twiddles.mem", profile0_inverse);
        $readmemh("generated_dual_butterfly_prefetch4/profile1/inverse_twiddles.mem", profile1_inverse);
        $readmemh("generated_dual_butterfly_prefetch4/profile0/inverse_scale_factors.mem", profile0_scale);
        $readmemh("generated_dual_butterfly_prefetch4/profile1/inverse_scale_factors.mem", profile1_scale);

        $readmemh(
            "generated_dual_butterfly_prefetch4/product0_tower0_a.mem",
            product0_tower0_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product0_tower0_b.mem",
            product0_tower0_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product0_tower0_expected.mem",
            product0_tower0_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product0_tower1_a.mem",
            product0_tower1_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product0_tower1_b.mem",
            product0_tower1_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product0_tower1_expected.mem",
            product0_tower1_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product1_tower0_a.mem",
            product1_tower0_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product1_tower0_b.mem",
            product1_tower0_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product1_tower0_expected.mem",
            product1_tower0_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product1_tower1_a.mem",
            product1_tower1_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product1_tower1_b.mem",
            product1_tower1_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product1_tower1_expected.mem",
            product1_tower1_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product2_tower0_a.mem",
            product2_tower0_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product2_tower0_b.mem",
            product2_tower0_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product2_tower0_expected.mem",
            product2_tower0_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product2_tower1_a.mem",
            product2_tower1_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product2_tower1_b.mem",
            product2_tower1_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product2_tower1_expected.mem",
            product2_tower1_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product3_tower0_a.mem",
            product3_tower0_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product3_tower0_b.mem",
            product3_tower0_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product3_tower0_expected.mem",
            product3_tower0_expected
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product3_tower1_a.mem",
            product3_tower1_a
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product3_tower1_b.mem",
            product3_tower1_b
        );
        $readmemh(
            "generated_dual_butterfly_prefetch4/product3_tower1_expected.mem",
            product3_tower1_expected
        );

        $display("PASS: loaded four distinct OpenFHE prefetch products");

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        $display("START: streaming paired q0/q1 runtime profile");
        send_dual_profile();

        while (!profile_ready)
            @(posedge clk);

        if (protocol_error)
        begin
            $display("FAIL: protocol error after profile");
            $fatal(1);
        end

        if (active_modulus_lane0 !== Q0 || active_modulus_lane1 !== Q1)
        begin
            $display(
                "FAIL MODULI lane0=%0d lane1=%0d",
                active_modulus_lane0,
                active_modulus_lane1
            );
            $fatal(1);
        end

        count_batch_traffic = 1'b1;

        $display("START: prefetching one product ahead across batch four");

        fork
            send_prefetch_batch4();
            receive_prefetch_batch4();
        join

        @(negedge clk);
        count_batch_traffic = 1'b0;

        if (protocol_error)
        begin
            $display("FAIL: protocol error after prefetch batch");
            $fatal(1);
        end

        if (completed_profiles !== 32'd1)
        begin
            $display("FAIL PROFILE COUNT result=%0d", completed_profiles);
            $fatal(1);
        end

        if (completed_products !== BATCH_COUNT)
        begin
            $display("FAIL PRODUCT COUNT result=%0d", completed_products);
            $fatal(1);
        end

        if (completed_batches !== 32'd1)
        begin
            $display("FAIL BATCH COUNT result=%0d", completed_batches);
            $fatal(1);
        end

        if (completed_prefetches !== BATCH_COUNT - 1)
        begin
            $display("FAIL PREFETCH COUNT result=%0d", completed_prefetches);
            $fatal(1);
        end

        if (completed_refills !== BATCH_COUNT - 1)
        begin
            $display("FAIL REFILL COUNT result=%0d", completed_refills);
            $fatal(1);
        end

        if (batch_input_handshakes !== BATCH_INPUT_WORDS)
        begin
            $display("FAIL INPUT WORDS result=%0d expected=%0d", batch_input_handshakes, BATCH_INPUT_WORDS);
            $fatal(1);
        end

        if (batch_output_handshakes !== BATCH_OUTPUT_WORDS)
        begin
            $display("FAIL OUTPUT WORDS result=%0d expected=%0d", batch_output_handshakes, BATCH_OUTPUT_WORDS);
            $fatal(1);
        end

        if (batch_input_tlast_handshakes !== 1 || batch_output_tlast_handshakes !== 1)
        begin
            $display(
                "FAIL TLAST COUNTS input=%0d output=%0d",
                batch_input_tlast_handshakes,
                batch_output_tlast_handshakes
            );
            $fatal(1);
        end

        if (input_words_at_first_output < 2 + 2 * 2 * N)
        begin
            $display(
                "FAIL PREFETCH OVERLAP first_output_input_words=%0d expected_at_least=%0d",
                input_words_at_first_output,
                2 + 2 * 2 * N
            );
            $fatal(1);
        end

        if (core_cycles_lane0 !== EXPECTED_CYCLES || core_cycles_lane1 !== EXPECTED_CYCLES)
        begin
            $display(
                "FAIL CYCLES lane0=%0d lane1=%0d expected=%0d",
                core_cycles_lane0,
                core_cycles_lane1,
                EXPECTED_CYCLES
            );
            $fatal(1);
        end

        if (modular_multiplications_lane0 !== 17'd90112 || modular_multiplications_lane1 !== 17'd90112)
        begin
            $display(
                "FAIL MULTIPLICATIONS lane0=%0d lane1=%0d",
                modular_multiplications_lane0,
                modular_multiplications_lane1
            );
            $fatal(1);
        end

        $display("PASS: product 0 loaded directly into the arithmetic stores");
        $display("PASS: products 1 through 3 were prefetched during prior computation");
        $display("PASS: same-address read-then-write refill preserved every result");
        $display("PASS: four distinct q0/q1 products exactly equal OpenFHE");
        $display("PASS: randomized input gaps and output backpressure");
        $display("PASS: exactly one input TLAST and one output TLAST");
        $display("PASS: arithmetic core cycle count remains unchanged");
        $display("PASS: expected additional storage is 16 RAMB36 across two towers");
        $display("Prefetched products: %0d", completed_prefetches);
        $display("Refilled products: %0d", completed_refills);
        $display("Per-product core cycles: %0d", core_cycles_lane0);
        $finish;
    end

endmodule
