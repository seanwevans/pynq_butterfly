`timescale 1ns/1ps

module tb_evalmul3_bv_keyreuse_multi_pair_session_axis_core;

    localparam integer N =
        32;

    localparam integer BATCH_COUNT =
        8;

    localparam integer DIGIT_COUNT =
        12;

    localparam integer PAIR_COUNT =
        6;

    localparam integer WORDS_PER_COEFFICIENT =
        4 * BATCH_COUNT
        + DIGIT_COUNT
            * (2 + BATCH_COUNT);

    localparam integer PAYLOAD_WORDS_PER_PAIR =
        N * WORDS_PER_COEFFICIENT;

    localparam integer EXPECTED_WORDS_PER_PAIR =
        N * BATCH_COUNT * 2;

    localparam integer TOTAL_PROFILE_WORDS =
        PAIR_COUNT * 2;

    localparam integer TOTAL_PAYLOAD_WORDS =
        PAIR_COUNT
        * PAYLOAD_WORDS_PER_PAIR;

    localparam integer TOTAL_EXPECTED_WORDS =
        PAIR_COUNT
        * EXPECTED_WORDS_PER_PAIR;

    localparam logic [31:0] COMMAND_PROFILE_TABLE =
        32'h524c5054;  // "RLPT"

    localparam logic [31:0] COMMAND_MULTI_PAIR =
        32'h524c4d50;  // "RLMP"

    logic clk;
    logic reset_n;

    logic [63:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [63:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic protocol_error;
    logic profile_ready;
    logic accelerator_busy;

    logic [63:0] active_modulus;
    logic [61:0] active_modulus_mu;
    logic [31:0] active_batch_size;
    logic [31:0] active_digit_count;

    logic [31:0] completed_profiles;
    logic [31:0] completed_ciphertexts;
    logic [31:0] completed_batches;
    logic [31:0] completed_pairs;
    logic [31:0] completed_coefficients;

    logic [63:0] profile_words [0:TOTAL_PROFILE_WORDS-1];
    logic [63:0] payload_words [0:TOTAL_PAYLOAD_WORDS-1];
    logic [63:0] expected_words [0:TOTAL_EXPECTED_WORDS-1];

    integer cycle_count;
    integer received_words;
    integer intermediate_child_tlast_count;
    integer accepted_pair_commands;
    integer output_backpressure_cycles;

    string vector_root;
    string profile_path;
    string payload_path;
    string expected_path;

    evalmul3_bv_keyreuse_multi_pair_session_axis_core #(
        .N                (N),
        .MAX_BATCH        (8),
        .MIN_BATCH        (8),
        .MAX_DIGITS       (16),
        .EVAL_META_DEPTH  (16),
        .BV_META_DEPTH    (32),
        .MAX_PAIR_COUNT   (6)
    ) dut (
        .clk                    (clk),
        .reset_n                (reset_n),

        .s_axis_tdata           (s_axis_tdata),
        .s_axis_tvalid          (s_axis_tvalid),
        .s_axis_tready          (s_axis_tready),
        .s_axis_tlast           (s_axis_tlast),

        .m_axis_tdata           (m_axis_tdata),
        .m_axis_tvalid          (m_axis_tvalid),
        .m_axis_tready          (m_axis_tready),
        .m_axis_tlast           (m_axis_tlast),

        .protocol_error         (protocol_error),
        .profile_ready          (profile_ready),
        .accelerator_busy       (accelerator_busy),

        .active_modulus         (active_modulus),
        .active_modulus_mu      (active_modulus_mu),
        .active_batch_size      (active_batch_size),
        .active_digit_count     (active_digit_count),

        .completed_profiles     (completed_profiles),
        .completed_ciphertexts  (completed_ciphertexts),
        .completed_batches      (completed_batches),
        .completed_pairs        (completed_pairs),
        .completed_coefficients (completed_coefficients)
    );

    always #5 clk =
        !clk;

    task automatic send_word(
        input logic [63:0] data_value,
        input logic        last_value
    );
    begin
        @(negedge clk);

        s_axis_tdata =
            data_value;

        s_axis_tlast =
            last_value;

        s_axis_tvalid =
            1'b1;

        while (!s_axis_tready)
        begin
            @(negedge clk);
        end

        @(negedge clk);

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        s_axis_tdata =
            64'd0;
    end
    endtask

    task automatic send_profile_table;
        integer pair_index;
    begin
        $display(
            "PROGRESS: loading six-pair RLPT profile table"
        );

        send_word(
            {
                COMMAND_PROFILE_TABLE,
                COMMAND_PROFILE_TABLE
            },
            1'b0
        );

        send_word(
            {
                32'd6,
                32'd6
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
                profile_words[
                    pair_index * 2
                ],
                1'b0
            );

            send_word(
                profile_words[
                    pair_index * 2 + 1
                ],
                pair_index + 1
                    == PAIR_COUNT
            );
        end

        wait (profile_ready);
    end
    endtask

    task automatic send_pair_frame(
        input integer pair_index
    );
        integer payload_index;
        integer payload_start;
        integer payload_end;
    begin
        $display(
            "PROGRESS: submitting RLMP pair frame %0d",
            pair_index
        );

        send_word(
            {
                COMMAND_MULTI_PAIR,
                COMMAND_MULTI_PAIR
            },
            1'b0
        );

        send_word(
            {
                32'd12,
                32'd8
            },
            1'b0
        );

        send_word(
            {
                32'd6,
                pair_index[31:0]
            },
            1'b0
        );

        payload_start =
            pair_index
            * PAYLOAD_WORDS_PER_PAIR;

        payload_end =
            payload_start
            + PAYLOAD_WORDS_PER_PAIR;

        for (
            payload_index = payload_start;
            payload_index < payload_end;
            payload_index = payload_index + 1
        )
        begin
            send_word(
                payload_words[
                    payload_index
                ],
                payload_index + 1
                    == payload_end
            );
        end
    end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            cycle_count <=
                0;

            received_words <=
                0;

            intermediate_child_tlast_count <=
                0;

            accepted_pair_commands <=
                0;

            output_backpressure_cycles <=
                0;
        end
        else
        begin
            cycle_count <=
                cycle_count + 1;

            /*
             * Deterministic backpressure proves that intermediate child TLAST
             * suppression is independent of a continuously-ready sink.
             */
            m_axis_tready <=
                cycle_count[3:0]
                != 4'h5
                && cycle_count[5:2]
                != 4'hd;

            if (
                m_axis_tvalid
                && !m_axis_tready
            )
            begin
                output_backpressure_cycles <=
                    output_backpressure_cycles
                    + 1;
            end

            if (
                s_axis_tvalid
                && s_axis_tready
                && s_axis_tdata
                    == {
                        COMMAND_MULTI_PAIR,
                        COMMAND_MULTI_PAIR
                    }
            )
            begin
                accepted_pair_commands <=
                    accepted_pair_commands
                    + 1;
            end

            if (
                dut.core_m_axis_tvalid
                && dut.core_m_axis_tready
                && dut.core_m_axis_tlast
                && !dut.final_pair
            )
            begin
                intermediate_child_tlast_count <=
                    intermediate_child_tlast_count
                    + 1;
            end

            if (
                m_axis_tvalid
                && m_axis_tready
            )
            begin
                if (
                    m_axis_tdata
                    !== expected_words[
                        received_words
                    ]
                )
                begin
                    $display(
                        "ERROR: output word %0d mismatch: got=%016x expected=%016x",
                        received_words,
                        m_axis_tdata,
                        expected_words[
                            received_words
                        ]
                    );

                    $fatal(1);
                end

                if (
                    m_axis_tlast
                    != (
                        received_words + 1
                        == TOTAL_EXPECTED_WORDS
                    )
                )
                begin
                    $display(
                        "ERROR: output TLAST mismatch at word %0d",
                        received_words
                    );

                    $fatal(1);
                end

                received_words <=
                    received_words
                    + 1;
            end

            if (cycle_count > 2500000)
            begin
                $display(
                    "ERROR: multi-pair session simulation timeout"
                );

                $fatal(1);
            end
        end
    end

    initial
    begin
        clk =
            1'b0;

        reset_n =
            1'b0;

        s_axis_tdata =
            64'd0;

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        m_axis_tready =
            1'b0;

        if (!$value$plusargs(
            "VECTOR_ROOT=%s",
            vector_root
        ))
        begin
            vector_root =
                "tests/generated/bv_keyreuse_multi_pair_session";
        end

        profile_path =
            {
                vector_root,
                "/profiles.hex"
            };

        payload_path =
            {
                vector_root,
                "/payload.hex"
            };

        expected_path =
            {
                vector_root,
                "/expected.hex"
            };

        $display(
            "PROGRESS: loading multi-pair vectors from %s",
            vector_root
        );

        $readmemh(
            profile_path,
            profile_words
        );

        $readmemh(
            payload_path,
            payload_words
        );

        $readmemh(
            expected_path,
            expected_words
        );

        repeat (8)
        begin
            @(negedge clk);
        end

        reset_n =
            1'b1;

        send_profile_table();

        if (completed_profiles != PAIR_COUNT)
        begin
            $display(
                "ERROR: completed_profiles=%0d expected=%0d",
                completed_profiles,
                PAIR_COUNT
            );

            $fatal(1);
        end

        /*
         * This models one persistent S2MM receive transaction: all six pair
         * frames are submitted before waiting for the sole external TLAST.
         */
        send_pair_frame(0);
        send_pair_frame(1);
        send_pair_frame(2);
        send_pair_frame(3);
        send_pair_frame(4);
        send_pair_frame(5);

        wait (
            received_words
            == TOTAL_EXPECTED_WORDS
        );

        wait (!accelerator_busy);

        repeat (8)
        begin
            @(negedge clk);
        end

        if (protocol_error)
        begin
            $display(
                "ERROR: protocol_error asserted"
            );

            $fatal(1);
        end

        if (
            accepted_pair_commands
            != PAIR_COUNT
        )
        begin
            $display(
                "ERROR: accepted_pair_commands=%0d expected=%0d",
                accepted_pair_commands,
                PAIR_COUNT
            );

            $fatal(1);
        end

        if (
            intermediate_child_tlast_count
            != PAIR_COUNT - 1
        )
        begin
            $display(
                "ERROR: suppressed intermediate child TLAST count=%0d expected=%0d",
                intermediate_child_tlast_count,
                PAIR_COUNT - 1
            );

            $fatal(1);
        end

        if (output_backpressure_cycles == 0)
        begin
            $display(
                "ERROR: testbench applied no output backpressure"
            );

            $fatal(1);
        end

        if (completed_pairs != PAIR_COUNT)
        begin
            $display(
                "ERROR: completed_pairs=%0d expected=%0d",
                completed_pairs,
                PAIR_COUNT
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
            completed_ciphertexts
            != BATCH_COUNT
        )
        begin
            $display(
                "ERROR: completed_ciphertexts=%0d expected=%0d",
                completed_ciphertexts,
                BATCH_COUNT
            );

            $fatal(1);
        end

        $display(
            "MULTI_PAIR_SESSION_OUTPUT_WORDS=%0d",
            received_words
        );

        $display(
            "MULTI_PAIR_SESSION_INTERMEDIATE_TLAST_SUPPRESSED=%0d",
            intermediate_child_tlast_count
        );

        $display(
            "MULTI_PAIR_SESSION_OUTPUT_BACKPRESSURE_CYCLES=%0d",
            output_backpressure_cycles
        );

        $display(
            "PASS: exact six-pair persistent-output session matches OpenFHE"
        );

        $finish;
    end

endmodule
