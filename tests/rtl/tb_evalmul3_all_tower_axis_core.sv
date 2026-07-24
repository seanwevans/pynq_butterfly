`timescale 1ns/1ps

module tb_evalmul3_all_tower_axis_core;

    localparam integer N = 8;
    localparam integer PAIR_COUNT = 3;
    localparam integer BATCH_COUNT = 2;

    localparam integer OUTPUT_WORDS =
        PAIR_COUNT
        * BATCH_COUNT
        * N
        * 3;

    localparam logic [31:0] COMMAND_PROFILE_TABLE =
        32'h45565054;  // EVPT

    localparam logic [31:0] COMMAND_ALL_PAIRS =
        32'h45563132;  // EV12

    logic clk;
    logic reset_n;

    logic [63:0] s_axis_tdata;
    logic        s_axis_tvalid;
    wire         s_axis_tready;
    logic        s_axis_tlast;

    wire [63:0]  m_axis_tdata;
    wire         m_axis_tvalid;
    logic        m_axis_tready;
    wire         m_axis_tlast;

    wire         protocol_error;
    wire         profile_ready;
    wire         accelerator_busy;
    wire [63:0]  active_modulus;
    wire [61:0]  active_modulus_mu;
    wire [31:0]  active_batch_size;
    wire [31:0]  completed_profiles;
    wire [31:0]  completed_ciphertexts;
    wire [31:0]  completed_batches;
    wire [31:0]  launched_coefficients;

    logic [31:0] modulus [0:PAIR_COUNT-1][0:1];
    logic [30:0] mu      [0:PAIR_COUNT-1][0:1];

    logic [63:0] expected [0:OUTPUT_WORDS-1];

    integer expected_write_index;
    integer received_words;
    integer ready_counter;
    integer timeout_counter;
    integer watchdog_cycles;
    integer last_outer_state;
    integer last_core_state;
    integer accepted_ev12_words;

    evalmul3_all_tower_axis_core #(
        .N              (N),
        .FIFO_DEPTH     (8),
        .MAX_PAIR_COUNT (6)
    ) dut (
        .clk                   (clk),
        .reset_n               (reset_n),

        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tvalid         (s_axis_tvalid),
        .s_axis_tready         (s_axis_tready),
        .s_axis_tlast          (s_axis_tlast),

        .m_axis_tdata          (m_axis_tdata),
        .m_axis_tvalid         (m_axis_tvalid),
        .m_axis_tready         (m_axis_tready),
        .m_axis_tlast          (m_axis_tlast),

        .protocol_error        (protocol_error),
        .profile_ready         (profile_ready),
        .accelerator_busy      (accelerator_busy),

        .active_modulus        (active_modulus),
        .active_modulus_mu     (active_modulus_mu),

        .active_batch_size     (active_batch_size),
        .completed_profiles    (completed_profiles),
        .completed_ciphertexts (completed_ciphertexts),
        .completed_batches     (completed_batches),
        .launched_coefficients (launched_coefficients)
    );

    initial
    begin
        clk =
            1'b0;

        forever
        begin
            #5 clk =
                ~clk;
        end
    end

    function automatic [31:0] operand_value;
        input integer pair_index;
        input integer ciphertext_index;
        input integer coefficient_index;
        input integer operand_index;
        input integer lane_index;
        input [31:0] q;

        longint unsigned raw_value;
        begin
            raw_value =
                100003
                + pair_index * 1000003
                + ciphertext_index * 10007
                + coefficient_index * 101
                + operand_index * 1009
                + lane_index * 17;

            operand_value =
                raw_value % q;
        end
    endfunction

    function automatic [31:0] modular_product;
        input [31:0] a;
        input [31:0] b;
        input [31:0] q;

        longint unsigned product;
        begin
            product =
                a;

            product =
                product * b;

            modular_product =
                product % q;
        end
    endfunction

    function automatic [31:0] modular_add;
        input [31:0] a;
        input [31:0] b;
        input [31:0] q;

        logic [32:0] sum;
        begin
            sum = {
                1'b0,
                a
            } + {
                1'b0,
                b
            };

            modular_add =
                sum >= q
                    ? sum - q
                    : sum[31:0];
        end
    endfunction

    task automatic send_word;
        input [63:0] data;
        input        last;

        begin
            @(negedge clk);

            s_axis_tdata =
                data;

            s_axis_tvalid =
                1'b1;

            s_axis_tlast =
                last;

            do
            begin
                @(posedge clk);
            end
            while (!s_axis_tready);

            @(negedge clk);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;

            s_axis_tdata =
                64'd0;
        end
    endtask

    task automatic build_expected;
        integer pair_index;
        integer ciphertext_index;
        integer coefficient_index;
        integer lane_index;

        logic [31:0] a0 [0:1];
        logic [31:0] a1 [0:1];
        logic [31:0] b0 [0:1];
        logic [31:0] b1 [0:1];

        logic [31:0] p00 [0:1];
        logic [31:0] p01 [0:1];
        logic [31:0] p10 [0:1];
        logic [31:0] p11 [0:1];

        logic [31:0] c1 [0:1];

        begin
            expected_write_index =
                0;

            for (
                pair_index = 0;
                pair_index < PAIR_COUNT;
                pair_index = pair_index + 1
            )
            begin
                for (
                    ciphertext_index = 0;
                    ciphertext_index < BATCH_COUNT;
                    ciphertext_index = ciphertext_index + 1
                )
                begin
                    for (
                        coefficient_index = 0;
                        coefficient_index < N;
                        coefficient_index = coefficient_index + 1
                    )
                    begin
                        for (
                            lane_index = 0;
                            lane_index < 2;
                            lane_index = lane_index + 1
                        )
                        begin
                            a0[lane_index] =
                                operand_value(
                                    pair_index,
                                    ciphertext_index,
                                    coefficient_index,
                                    0,
                                    lane_index,
                                    modulus[pair_index][lane_index]
                                );

                            a1[lane_index] =
                                operand_value(
                                    pair_index,
                                    ciphertext_index,
                                    coefficient_index,
                                    1,
                                    lane_index,
                                    modulus[pair_index][lane_index]
                                );

                            b0[lane_index] =
                                operand_value(
                                    pair_index,
                                    ciphertext_index,
                                    coefficient_index,
                                    2,
                                    lane_index,
                                    modulus[pair_index][lane_index]
                                );

                            b1[lane_index] =
                                operand_value(
                                    pair_index,
                                    ciphertext_index,
                                    coefficient_index,
                                    3,
                                    lane_index,
                                    modulus[pair_index][lane_index]
                                );

                            p00[lane_index] =
                                modular_product(
                                    a0[lane_index],
                                    b0[lane_index],
                                    modulus[pair_index][lane_index]
                                );

                            p01[lane_index] =
                                modular_product(
                                    a0[lane_index],
                                    b1[lane_index],
                                    modulus[pair_index][lane_index]
                                );

                            p10[lane_index] =
                                modular_product(
                                    a1[lane_index],
                                    b0[lane_index],
                                    modulus[pair_index][lane_index]
                                );

                            p11[lane_index] =
                                modular_product(
                                    a1[lane_index],
                                    b1[lane_index],
                                    modulus[pair_index][lane_index]
                                );

                            c1[lane_index] =
                                modular_add(
                                    p01[lane_index],
                                    p10[lane_index],
                                    modulus[pair_index][lane_index]
                                );
                        end

                        expected[expected_write_index] = {
                            p00[1],
                            p00[0]
                        };

                        expected_write_index =
                            expected_write_index + 1;

                        expected[expected_write_index] = {
                            c1[1],
                            c1[0]
                        };

                        expected_write_index =
                            expected_write_index + 1;

                        expected[expected_write_index] = {
                            p11[1],
                            p11[0]
                        };

                        expected_write_index =
                            expected_write_index + 1;
                    end
                end
            end

            if (expected_write_index != OUTPUT_WORDS)
            begin
                $display(
                    "ERROR: expected queue length %0d, wanted %0d",
                    expected_write_index,
                    OUTPUT_WORDS
                );

                $fatal(1);
            end
        end
    endtask

    task automatic send_profile_table;
        integer pair_index;

        begin
            send_word(
                {
                    COMMAND_PROFILE_TABLE,
                    COMMAND_PROFILE_TABLE
                },
                1'b0
            );

            send_word(
                {
                    PAIR_COUNT,
                    PAIR_COUNT
                },
                1'b0
            );

            for (
                pair_index = 0;
                pair_index < PAIR_COUNT;
                pair_index = pair_index + 1
            )
            begin
                send_word(
                    {
                        modulus[pair_index][1],
                        modulus[pair_index][0]
                    },
                    1'b0
                );

                send_word(
                    {
                        1'b0,
                        mu[pair_index][1],
                        1'b0,
                        mu[pair_index][0]
                    },
                    pair_index + 1 == PAIR_COUNT
                );
            end
        end
    endtask

    task automatic send_all_pair_batch;
        integer pair_index;
        integer ciphertext_index;
        integer coefficient_index;
        integer operand_index;

        logic [31:0] lane0;
        logic [31:0] lane1;
        logic final_word;

        begin
            send_word(
                {
                    COMMAND_ALL_PAIRS,
                    COMMAND_ALL_PAIRS
                },
                1'b0
            );

            send_word(
                {
                    PAIR_COUNT,
                    BATCH_COUNT
                },
                1'b0
            );

            for (
                pair_index = 0;
                pair_index < PAIR_COUNT;
                pair_index = pair_index + 1
            )
            begin
                for (
                    ciphertext_index = 0;
                    ciphertext_index < BATCH_COUNT;
                    ciphertext_index = ciphertext_index + 1
                )
                begin
                    for (
                        coefficient_index = 0;
                        coefficient_index < N;
                        coefficient_index = coefficient_index + 1
                    )
                    begin
                        for (
                            operand_index = 0;
                            operand_index < 4;
                            operand_index = operand_index + 1
                        )
                        begin
                            lane0 =
                                operand_value(
                                    pair_index,
                                    ciphertext_index,
                                    coefficient_index,
                                    operand_index,
                                    0,
                                    modulus[pair_index][0]
                                );

                            lane1 =
                                operand_value(
                                    pair_index,
                                    ciphertext_index,
                                    coefficient_index,
                                    operand_index,
                                    1,
                                    modulus[pair_index][1]
                                );

                            final_word =
                                pair_index + 1 == PAIR_COUNT
                                && ciphertext_index + 1 == BATCH_COUNT
                                && coefficient_index + 1 == N
                                && operand_index == 3;

                            send_word(
                                {
                                    lane1,
                                    lane0
                                },
                                final_word
                            );
                        end
                    end
                end
            end
        end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            ready_counter <=
                0;

            m_axis_tready <=
                1'b0;
        end
        else
        begin
            ready_counter <=
                ready_counter + 1;

            m_axis_tready <=
                ready_counter % 11 != 3
                && ready_counter % 13 != 7;
        end
    end

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            last_outer_state <=
                -1;

            last_core_state <=
                -1;

            accepted_ev12_words <=
                0;
        end
        else
        begin
            if (dut.state != last_outer_state)
            begin
                $display(
                    "TRACE: cycle=%0d outer_state=%0d pair=%0d/%0d",
                    watchdog_cycles,
                    dut.state,
                    dut.current_pair_index,
                    dut.active_pair_count
                );

                last_outer_state <=
                    dut.state;
            end

            if (
                dut.two_tower_core.input_state
                != last_core_state
            )
            begin
                $display(
                    "TRACE: cycle=%0d core_state=%0d reserved=%0d fifo=%0d",
                    watchdog_cycles,
                    dut.two_tower_core.input_state,
                    dut.two_tower_core.reserved_count,
                    dut.two_tower_core.fifo_count
                );

                last_core_state <=
                    dut.two_tower_core.input_state;
            end

            if (
                dut.external_input_handshake
                && dut.state == 10
            )
            begin
                accepted_ev12_words <=
                    accepted_ev12_words + 1;

                if (
                    accepted_ev12_words[3:0]
                    == 4'hf
                )
                begin
                    $display(
                        "TRACE: cycle=%0d accepted_ev12_words=%0d pair=%0d ct=%0d coeff=%0d phase=%0d",
                        watchdog_cycles,
                        accepted_ev12_words + 1,
                        dut.current_pair_index,
                        dut.input_ciphertext_index,
                        dut.input_coefficient_index,
                        dut.input_operand_phase
                    );
                end
            end

            if (
                watchdog_cycles != 0
                && watchdog_cycles[5:0] == 0
            )
            begin
                $display(
                    "HEARTBEAT: cycle=%0d outer=%0d core=%0d pair=%0d ready=%0b out_valid=%0b received=%0d",
                    watchdog_cycles,
                    dut.state,
                    dut.two_tower_core.input_state,
                    dut.current_pair_index,
                    s_axis_tready,
                    m_axis_tvalid,
                    received_words
                );
            end
        end
    end

    always @(posedge clk)
    begin
        if (
            reset_n
            && dut.pair_output_complete
        )
        begin
            $display(
                "PROGRESS: pair %0d complete; received_words=%0d",
                dut.current_pair_index,
                received_words
            );
        end
    end

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            received_words <=
                0;
        end
        else if (
            m_axis_tvalid
            && m_axis_tready
        )
        begin
            if (
                m_axis_tdata
                !== expected[received_words]
            )
            begin
                $display(
                    "ERROR: output word %0d mismatch: got %h expected %h",
                    received_words,
                    m_axis_tdata,
                    expected[received_words]
                );

                $fatal(1);
            end

            if (
                m_axis_tlast
                != (received_words + 1 == OUTPUT_WORDS)
            )
            begin
                $display(
                    "ERROR: output TLAST mismatch at word %0d",
                    received_words
                );

                $fatal(1);
            end

            received_words <=
                received_words + 1;
        end
    end

    initial
    begin
        watchdog_cycles =
            0;

        wait (reset_n);

        while (watchdog_cycles < 512)
        begin
            @(posedge clk);

            watchdog_cycles =
                watchdog_cycles + 1;
        end

        $display(
            "ERROR: all-pair RTL watchdog expired after 512 cycles"
        );

        $display(
            "  outer_state=%0d pair=%0d/%0d input_ct=%0d coeff=%0d phase=%0d",
            dut.state,
            dut.current_pair_index,
            dut.active_pair_count,
            dut.input_ciphertext_index,
            dut.input_coefficient_index,
            dut.input_operand_phase
        );

        $display(
            "  core_state=%0d core_busy=%0b core_ready=%0b core_out_valid=%0b core_out_last=%0b",
            dut.two_tower_core.input_state,
            dut.core_accelerator_busy,
            dut.core_s_axis_tready,
            dut.core_m_axis_tvalid,
            dut.core_m_axis_tlast
        );

        $display(
            "  reserved=%0d fifo=%0d received=%0d/%0d",
            dut.two_tower_core.reserved_count,
            dut.two_tower_core.fifo_count,
            received_words,
            OUTPUT_WORDS
        );

        $fatal(1);
    end

    initial
    begin
        modulus[0][0] =
            32'd1073692673;

        modulus[0][1] =
            32'd1073668097;

        modulus[1][0] =
            32'd1073651713;

        modulus[1][1] =
            32'd1073643521;

        modulus[2][0] =
            32'd1073627137;

        modulus[2][1] =
            32'd1073602561;

        mu[0][0] =
            64'h1000000000000000 / modulus[0][0];

        mu[0][1] =
            64'h1000000000000000 / modulus[0][1];

        mu[1][0] =
            64'h1000000000000000 / modulus[1][0];

        mu[1][1] =
            64'h1000000000000000 / modulus[1][1];

        mu[2][0] =
            64'h1000000000000000 / modulus[2][0];

        mu[2][1] =
            64'h1000000000000000 / modulus[2][1];

        reset_n =
            1'b0;

        s_axis_tdata =
            64'd0;

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        received_words =
            0;

        $display("PROGRESS: building expected results");
        build_expected();
        $display("PROGRESS: expected results ready");

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n =
            1'b1;

        $display("PROGRESS: sending EVPT profile table");
        send_profile_table();
        $display("PROGRESS: EVPT profile table accepted");

        if (!profile_ready)
        begin
            @(posedge clk);
        end

        if (!profile_ready)
        begin
            $display(
                "ERROR: profile table did not become ready"
            );

            $fatal(1);
        end

        $display("PROGRESS: sending EV12 all-pair batch");
        send_all_pair_batch();
        $display("PROGRESS: EV12 input frame accepted");

        timeout_counter =
            0;

        while (
            received_words < OUTPUT_WORDS
            && timeout_counter < 20000
        )
        begin
            @(posedge clk);

            timeout_counter =
                timeout_counter + 1;
        end

        if (received_words != OUTPUT_WORDS)
        begin
            $display(
                "ERROR: timeout: received %0d of %0d output words",
                received_words,
                OUTPUT_WORDS
            );

            $fatal(1);
        end

        repeat (10)
        begin
            @(posedge clk);
        end

        if (protocol_error)
        begin
            $display(
                "ERROR: protocol_error asserted"
            );

            $fatal(1);
        end

        if (accelerator_busy)
        begin
            $display(
                "ERROR: accelerator remained busy"
            );

            $fatal(1);
        end

        if (completed_profiles != PAIR_COUNT)
        begin
            $display(
                "ERROR: completed_profiles=%0d expected=%0d",
                completed_profiles,
                PAIR_COUNT
            );

            $fatal(1);
        end

        if (completed_ciphertexts != BATCH_COUNT)
        begin
            $display(
                "ERROR: completed_ciphertexts=%0d expected=%0d",
                completed_ciphertexts,
                BATCH_COUNT
            );

            $fatal(1);
        end

        if (completed_batches != 1)
        begin
            $display(
                "ERROR: completed_batches=%0d expected=1",
                completed_batches
            );

            $fatal(1);
        end

        if (
            launched_coefficients
            != PAIR_COUNT * BATCH_COUNT * N
        )
        begin
            $display(
                "ERROR: launched_coefficients=%0d expected=%0d",
                launched_coefficients,
                PAIR_COUNT * BATCH_COUNT * N
            );

            $fatal(1);
        end

        $display(
            "PASS: all-pair EVPT/EV12 exact with deterministic output backpressure"
        );

        $finish;
    end

endmodule
