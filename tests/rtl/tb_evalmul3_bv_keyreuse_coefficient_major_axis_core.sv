`timescale 1ns/1ps

module tb_evalmul3_bv_keyreuse_coefficient_major_axis_core;

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

    localparam logic [31:0] COMMAND_PROFILE =
        32'h524c5046;  // "RLPF"

    localparam logic [31:0] COMMAND_BATCH =
        32'h524c434d;  // "RLCM"

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
    logic [31:0] completed_coefficients;

    logic [63:0] profile_words [0:TOTAL_PROFILE_WORDS-1];
    logic [63:0] payload_words [0:TOTAL_PAYLOAD_WORDS-1];
    logic [63:0] expected_words [0:TOTAL_EXPECTED_WORDS-1];

    integer cycle_count;
    integer received_words;
    integer expected_index;
    integer current_output_pair;

    string vector_root;
    string profile_path;
    string payload_path;
    string expected_path;

    evalmul3_bv_keyreuse_coefficient_major_axis_core #(
        .N                (N),
        .MAX_BATCH        (8),
        .MIN_BATCH        (8),
        .MAX_DIGITS       (16),
        .EVAL_META_DEPTH  (16),
        .BV_META_DEPTH    (32)
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

    task automatic send_pair(
        input integer pair_index
    );
        integer payload_index;
        integer payload_start;
        integer payload_end;
    begin
        $display(
            "PROGRESS: pair %0d loading RLPF",
            pair_index
        );

        send_word(
            {
                COMMAND_PROFILE,
                COMMAND_PROFILE
            },
            1'b0
        );

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
            1'b1
        );

        wait (profile_ready);

        $display(
            "PROGRESS: pair %0d sending coefficient-major RLCM batch",
            pair_index
        );

        send_word(
            {
                COMMAND_BATCH,
                COMMAND_BATCH
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
                payload_words[payload_index],
                payload_index + 1
                    == payload_end
            );
        end

        wait (
            received_words
            == (pair_index + 1)
                * EXPECTED_WORDS_PER_PAIR
        );

        wait (!accelerator_busy);

        if (protocol_error)
        begin
            $display(
                "ERROR: protocol_error asserted after pair %0d",
                pair_index
            );

            $fatal(1);
        end

        $display(
            "PROGRESS: pair %0d exact; received_words=%0d",
            pair_index,
            received_words
        );
    end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            cycle_count <=
                0;

            m_axis_tready <=
                1'b0;
        end
        else
        begin
            cycle_count <=
                cycle_count + 1;

            m_axis_tready <=
                cycle_count[2:0] != 3'd2
                && cycle_count[3:0] != 4'd11;

            if (cycle_count > 800000)
            begin
                $display(
                    "ERROR: coefficient-major simulation watchdog fired"
                );

                $fatal(1);
            end
        end
    end

    always @(posedge clk)
    begin
        if (
            reset_n
            && m_axis_tvalid
            && m_axis_tready
        )
        begin
            if (
                m_axis_tdata
                !== expected_words[expected_index]
            )
            begin
                $display(
                    "ERROR: output mismatch index=%0d pair=%0d expected=%016h actual=%016h",
                    expected_index,
                    current_output_pair,
                    expected_words[expected_index],
                    m_axis_tdata
                );

                $fatal(1);
            end

            if (
                m_axis_tlast
                != (
                    (
                        expected_index + 1
                    )
                    % EXPECTED_WORDS_PER_PAIR
                    == 0
                )
            )
            begin
                $display(
                    "ERROR: TLAST mismatch index=%0d pair=%0d",
                    expected_index,
                    current_output_pair
                );

                $fatal(1);
            end

            expected_index <=
                expected_index + 1;

            received_words <=
                received_words + 1;

            if (
                (
                    expected_index + 1
                )
                % EXPECTED_WORDS_PER_PAIR
                == 0
            )
            begin
                current_output_pair <=
                    current_output_pair + 1;
            end
        end
    end

    integer pair_index;

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

        cycle_count =
            0;

        received_words =
            0;

        expected_index =
            0;

        current_output_pair =
            0;

        if (!$value$plusargs(
            "VECTOR_ROOT=%s",
            vector_root
        ))
        begin
            $display(
                "ERROR: missing +VECTOR_ROOT=<directory>"
            );

            $fatal(1);
        end

        profile_path = {
            vector_root,
            "/profiles.hex"
        };

        payload_path = {
            vector_root,
            "/payload.hex"
        };

        expected_path = {
            vector_root,
            "/expected.hex"
        };

        $display(
            "PROGRESS: loading coefficient-major vectors from %s",
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
            @(posedge clk);
        end

        reset_n =
            1'b1;

        repeat (4)
        begin
            @(posedge clk);
        end

        for (
            pair_index = 0;
            pair_index < PAIR_COUNT;
            pair_index = pair_index + 1
        )
        begin
            send_pair(pair_index);
        end

        repeat (16)
        begin
            @(posedge clk);
        end

        if (
            expected_index
            != TOTAL_EXPECTED_WORDS
        )
        begin
            $display(
                "ERROR: expected %0d words, received %0d",
                TOTAL_EXPECTED_WORDS,
                expected_index
            );

            $fatal(1);
        end

        if (
            completed_profiles
            != PAIR_COUNT
        )
        begin
            $display(
                "ERROR: completed_profiles=%0d expected=%0d",
                completed_profiles,
                PAIR_COUNT
            );

            $fatal(1);
        end

        if (
            completed_batches
            != PAIR_COUNT
        )
        begin
            $display(
                "ERROR: completed_batches=%0d expected=%0d",
                completed_batches,
                PAIR_COUNT
            );

            $fatal(1);
        end

        if (
            completed_ciphertexts
            != PAIR_COUNT * BATCH_COUNT
        )
        begin
            $display(
                "ERROR: completed_ciphertexts=%0d expected=%0d",
                completed_ciphertexts,
                PAIR_COUNT * BATCH_COUNT
            );

            $fatal(1);
        end

        if (
            completed_coefficients
            != PAIR_COUNT * N * BATCH_COUNT
        )
        begin
            $display(
                "ERROR: completed_coefficients=%0d expected=%0d",
                completed_coefficients,
                PAIR_COUNT * N * BATCH_COUNT
            );

            $fatal(1);
        end

        $display(
            "PASS: exact coefficient-major BV evaluation-key reuse across all six tower pairs"
        );

        $finish;
    end

endmodule
