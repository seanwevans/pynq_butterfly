`timescale 1ns/1ps

/*
 * Persistent-output multi-pair session wrapper for the exact coefficient-major
 * compute-drain-overlap OpenFHE BV core.
 *
 * The wrapped arithmetic core still processes one pair of Q towers at a time.
 * This wrapper stores all paired-tower Barrett profiles and allows one S2MM
 * receive transaction to span several independently sized MM2S pair frames.
 *
 * Profile-table frame:
 *
 *     word 0: { "RLPT", "RLPT" }
 *     word 1: { pair_count, pair_count }
 *
 *     repeated pair_count times:
 *         { q1,  q0  }
 *         { mu1, mu0 }
 *
 *     TLAST only on the final mu word.
 *
 * Pair frame:
 *
 *     word 0: { "RLMP", "RLMP" }
 *     word 1: { digit_count, ciphertext_count }
 *     word 2: { pair_count, pair_index }
 *
 *     then exactly:
 *
 *         N * (
 *             4*ciphertext_count
 *             + digit_count*(ciphertext_count+2)
 *         )
 *
 *     coefficient-major RLCM payload words.
 *
 * Every MM2S pair frame asserts TLAST on its own final payload word. The
 * wrapper forwards that marker to the child core so the child completes the
 * pair, but suppresses the corresponding output TLAST for all nonfinal pairs.
 * Only the final output word of the final pair carries external TLAST.
 *
 * The host can therefore:
 *
 *     1. arm one receive transfer for all pair outputs;
 *     2. submit one send transfer per pair;
 *     3. wait for the receive transfer only after the final pair.
 */
module evalmul3_bv_keyreuse_multi_pair_session_axis_core #(
    parameter integer N = 4096,
    parameter integer MAX_BATCH = 64,
    parameter integer MIN_BATCH = 8,
    parameter integer MAX_DIGITS = 16,
    parameter integer EVAL_META_DEPTH = 16,
    parameter integer BV_META_DEPTH = 32,
    parameter integer MAX_PAIR_COUNT = 6
) (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [63:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    output logic        protocol_error,
    output logic        profile_ready,
    output logic        accelerator_busy,

    output logic [63:0] active_modulus,
    output logic [61:0] active_modulus_mu,
    output logic [31:0] active_batch_size,
    output logic [31:0] active_digit_count,

    output logic [31:0] completed_profiles,
    output logic [31:0] completed_ciphertexts,
    output logic [31:0] completed_batches,
    output logic [31:0] completed_pairs,
    output logic [31:0] completed_coefficients
);

    localparam integer PAIR_INDEX_WIDTH =
        (MAX_PAIR_COUNT <= 2)
        ? 1
        : $clog2(MAX_PAIR_COUNT);

    /*
     * N is 32 in exact simulation and 4096 in production. Both are powers of
     * two, so payload_words = words_per_coefficient << N_SHIFT.
     */
    localparam integer N_SHIFT =
        $clog2(N);

    localparam logic [31:0] COMMAND_PROFILE =
        32'h524c5046;  // "RLPF"

    localparam logic [31:0] COMMAND_BATCH =
        32'h524c434d;  // "RLCM"

    localparam logic [31:0] COMMAND_PROFILE_TABLE =
        32'h524c5054;  // "RLPT"

    localparam logic [31:0] COMMAND_MULTI_PAIR =
        32'h524c4d50;  // "RLMP"

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PROFILE_COUNT,
        STATE_PROFILE_Q,
        STATE_PROFILE_MU,
        STATE_PAIR_COUNTS,
        STATE_PAIR_INDEX,
        STATE_INJECT_PROFILE_COMMAND,
        STATE_INJECT_PROFILE_Q,
        STATE_INJECT_PROFILE_MU,
        STATE_INJECT_BATCH_COMMAND,
        STATE_INJECT_BATCH_COUNT,
        STATE_FORWARD_PAIR_DATA,
        STATE_WAIT_PAIR_OUTPUT,
        STATE_DISCARD
    } state_t;

    state_t state;

    logic [63:0] profile_modulus [0:MAX_PAIR_COUNT-1];
    logic [63:0] profile_mu_word [0:MAX_PAIR_COUNT-1];

    logic [31:0] loading_pair_count;
    logic [31:0] loaded_pair_count;

    logic [PAIR_INDEX_WIDTH-1:0] profile_write_index;
    logic [PAIR_INDEX_WIDTH-1:0] current_pair_index;
    logic [PAIR_INDEX_WIDTH-1:0] expected_pair_index;

    logic profile_table_ready;
    logic session_active;

    logic [31:0] frame_batch_count;
    logic [31:0] frame_digit_count;

    logic [31:0] session_batch_count;
    logic [31:0] session_digit_count;

    logic [31:0] payload_words_remaining;
    logic        pair_input_complete;

    logic own_protocol_error;

    /*
     * Registered two-word payload FIFO.
     *
     * It breaks the child-ready -> external-ready combinational path while
     * still sustaining one logical 64-bit word per core clock.
     */
    logic [63:0] payload_data [0:1];
    logic        payload_last [0:1];
    logic        payload_write_pointer;
    logic        payload_read_pointer;
    logic [1:0]  payload_count;

    logic [63:0] injection_data;
    logic        injection_valid;
    logic        injection_last;

    logic [63:0] core_s_axis_tdata;
    logic        core_s_axis_tvalid;
    wire         core_s_axis_tready;
    logic        core_s_axis_tlast;

    wire [63:0]  core_m_axis_tdata;
    wire         core_m_axis_tvalid;
    logic        core_m_axis_tready;
    wire         core_m_axis_tlast;

    wire         core_protocol_error;
    wire         core_profile_ready;
    wire         core_accelerator_busy;

    wire [63:0]  core_active_modulus;
    wire [61:0]  core_active_modulus_mu;
    wire [31:0]  core_active_batch_size;
    wire [31:0]  core_active_digit_count;

    wire [31:0]  core_completed_profiles;
    wire [31:0]  core_completed_ciphertexts;
    wire [31:0]  core_completed_batches;
    wire [31:0]  core_completed_coefficients;

    wire external_input_handshake =
        s_axis_tvalid
        && s_axis_tready;

    wire core_input_handshake =
        core_s_axis_tvalid
        && core_s_axis_tready;

    wire core_output_handshake =
        core_m_axis_tvalid
        && core_m_axis_tready;

    wire payload_enqueue =
        state == STATE_FORWARD_PAIR_DATA
        && external_input_handshake;

    wire payload_dequeue =
        state == STATE_FORWARD_PAIR_DATA
        && payload_count != 0
        && core_s_axis_tready;

    wire payload_head_last =
        payload_last[
            payload_read_pointer
        ];

    wire profile_table_command =
        s_axis_tdata == {
            COMMAND_PROFILE_TABLE,
            COMMAND_PROFILE_TABLE
        };

    wire multi_pair_command =
        s_axis_tdata == {
            COMMAND_MULTI_PAIR,
            COMMAND_MULTI_PAIR
        };

    wire final_profile_word =
        profile_write_index + 1'b1
        == loading_pair_count;

    wire final_pair =
        current_pair_index + 1'b1
        == loaded_pair_count;

    wire payload_final_word =
        payload_words_remaining
        == 32'd1;

    wire pair_output_complete =
        core_output_handshake
        && core_m_axis_tlast;

    /*
     * Small bounded shift-add multiplier.
     *
     * The original 64-bit expression:
     *
     *     digit_count * (batch_count + 2)
     *
     * inferred four DSP48E1 cells in the session wrapper. That arithmetic is
     * only protocol-length bookkeeping, with:
     *
     *     0 <= digit_count <= 16
     *     0 <= batch_count + 2 <= 66
     *
     * This explicit five-bit shift-add implementation keeps the bookkeeping in
     * LUT/carry logic and reserves all DSP48E1 cells for the exact modular
     * arithmetic child.
     */
    function automatic logic [11:0] multiply_small_unsigned(
        input logic [4:0] digit_value,
        input logic [6:0] batch_plus_two_value
    );
        integer bit_index;
        logic [11:0] extended_batch_value;
    begin
        multiply_small_unsigned =
            12'd0;

        extended_batch_value = {
            5'd0,
            batch_plus_two_value
        };

        for (
            bit_index = 0;
            bit_index < 5;
            bit_index = bit_index + 1
        )
        begin
            if (digit_value[bit_index])
            begin
                multiply_small_unsigned =
                    multiply_small_unsigned
                    + (
                        extended_batch_value
                        << bit_index
                    );
            end
        end
    end
    endfunction

    wire [6:0] bounded_batch_plus_two =
        frame_batch_count[6:0]
        + 7'd2;

    wire [11:0] digit_batch_product =
        multiply_small_unsigned(
            frame_digit_count[4:0],
            bounded_batch_plus_two
        );

    wire [11:0] words_per_coefficient_small =
        (
            {
                5'd0,
                frame_batch_count[6:0]
            } << 2
        )
        + digit_batch_product;

    wire [63:0] words_per_coefficient = {
        52'd0,
        words_per_coefficient_small
    };

    wire [63:0] pair_payload_words =
        words_per_coefficient
        << N_SHIFT;

    /*
     * The previous dynamically widened multiplication is intentionally gone:
     *
     *     frame_digit_count * (frame_batch_count + 2)
     *     words_per_coefficient * N
     */
    assign protocol_error =
        own_protocol_error
        || core_protocol_error;

    assign profile_ready =
        profile_table_ready;

    assign accelerator_busy =
        state != STATE_IDLE
        || session_active
        || core_accelerator_busy;

    assign active_modulus =
        core_active_modulus;

    assign active_modulus_mu =
        core_active_modulus_mu;

    assign active_batch_size =
        session_active
        ? session_batch_count
        : core_active_batch_size;

    assign active_digit_count =
        session_active
        ? session_digit_count
        : core_active_digit_count;

    assign completed_coefficients =
        core_completed_coefficients;

    /*
     * Child output passes through unchanged except that intermediate pair TLAST
     * markers are suppressed. The receive DMA therefore remains active across
     * the whole session.
     */
    always @*
    begin
        m_axis_tdata =
            core_m_axis_tdata;

        m_axis_tvalid =
            core_m_axis_tvalid;

        core_m_axis_tready =
            m_axis_tready;

        m_axis_tlast =
            core_m_axis_tvalid
            && core_m_axis_tlast
            && final_pair;
    end

    /*
     * Internal RLPF/RLCM headers are emitted by a registered injection source.
     * Pair payload words come from the registered two-entry FIFO.
     */
    always @*
    begin
        s_axis_tready =
            1'b0;

        core_s_axis_tdata =
            injection_data;

        core_s_axis_tvalid =
            injection_valid;

        core_s_axis_tlast =
            injection_last;

        case (state)
            STATE_IDLE,
            STATE_PROFILE_COUNT,
            STATE_PROFILE_Q,
            STATE_PROFILE_MU,
            STATE_PAIR_COUNTS,
            STATE_PAIR_INDEX,
            STATE_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            STATE_FORWARD_PAIR_DATA:
            begin
                core_s_axis_tdata =
                    payload_data[
                        payload_read_pointer
                    ];

                core_s_axis_tvalid =
                    payload_count != 0;

                core_s_axis_tlast =
                    payload_head_last;

                s_axis_tready =
                    !pair_input_complete
                    && payload_count < 2;
            end

            default:
            begin
            end
        endcase
    end

    integer reset_index;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            loading_pair_count <=
                32'd0;

            loaded_pair_count <=
                32'd0;

            profile_write_index <=
                '0;

            current_pair_index <=
                '0;

            expected_pair_index <=
                '0;

            profile_table_ready <=
                1'b0;

            session_active <=
                1'b0;

            frame_batch_count <=
                32'd0;

            frame_digit_count <=
                32'd0;

            session_batch_count <=
                32'd0;

            session_digit_count <=
                32'd0;

            payload_words_remaining <=
                32'd0;

            pair_input_complete <=
                1'b0;

            injection_data <=
                64'd0;

            injection_valid <=
                1'b0;

            injection_last <=
                1'b0;

            own_protocol_error <=
                1'b0;

            completed_profiles <=
                32'd0;

            completed_ciphertexts <=
                32'd0;

            completed_batches <=
                32'd0;

            completed_pairs <=
                32'd0;

            for (
                reset_index = 0;
                reset_index < MAX_PAIR_COUNT;
                reset_index = reset_index + 1
            )
            begin
                profile_modulus[
                    reset_index
                ] <= 64'd0;

                profile_mu_word[
                    reset_index
                ] <= 64'd0;
            end
        end
        else
        begin
            case (state)
                STATE_IDLE:
                begin
                    if (external_input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            own_protocol_error <=
                                1'b1;
                        end
                        else if (
                            profile_table_command
                            && !session_active
                        )
                        begin
                            state <=
                                STATE_PROFILE_COUNT;
                        end
                        else if (
                            multi_pair_command
                            && profile_table_ready
                        )
                        begin
                            state <=
                                STATE_PAIR_COUNTS;
                        end
                        else
                        begin
                            own_protocol_error <=
                                1'b1;

                            state <=
                                STATE_DISCARD;
                        end
                    end
                end

                STATE_PROFILE_COUNT:
                begin
                    if (external_input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:0]
                                == 32'd0
                            || s_axis_tdata[63:32]
                                != s_axis_tdata[31:0]
                            || s_axis_tdata[31:0]
                                > MAX_PAIR_COUNT
                        )
                        begin
                            own_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            loading_pair_count <=
                                s_axis_tdata[31:0];

                            profile_write_index <=
                                '0;

                            profile_table_ready <=
                                1'b0;

                            state <=
                                STATE_PROFILE_Q;
                        end
                    end
                end

                STATE_PROFILE_Q:
                begin
                    if (external_input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:30]
                                != 2'b00
                            || s_axis_tdata[63:62]
                                != 2'b00
                            || !s_axis_tdata[29]
                            || !s_axis_tdata[61]
                        )
                        begin
                            own_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            profile_modulus[
                                profile_write_index
                            ] <= s_axis_tdata;

                            state <=
                                STATE_PROFILE_MU;
                        end
                    end
                end

                STATE_PROFILE_MU:
                begin
                    if (external_input_handshake)
                    begin
                        if (
                            s_axis_tlast
                                != final_profile_word
                            || s_axis_tdata[31]
                            || s_axis_tdata[63]
                        )
                        begin
                            own_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            profile_mu_word[
                                profile_write_index
                            ] <= s_axis_tdata;

                            if (final_profile_word)
                            begin
                                loaded_pair_count <=
                                    loading_pair_count;

                                expected_pair_index <=
                                    '0;

                                profile_table_ready <=
                                    1'b1;

                                completed_profiles <=
                                    completed_profiles
                                    + loading_pair_count;

                                state <=
                                    STATE_IDLE;
                            end
                            else
                            begin
                                profile_write_index <=
                                    profile_write_index
                                    + 1'b1;

                                state <=
                                    STATE_PROFILE_Q;
                            end
                        end
                    end
                end

                STATE_PAIR_COUNTS:
                begin
                    if (external_input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:0]
                                < MIN_BATCH
                            || s_axis_tdata[31:0]
                                > MAX_BATCH
                            || s_axis_tdata[63:32]
                                == 32'd0
                            || s_axis_tdata[63:32]
                                > MAX_DIGITS
                        )
                        begin
                            own_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            frame_batch_count <=
                                s_axis_tdata[31:0];

                            frame_digit_count <=
                                s_axis_tdata[63:32];

                            state <=
                                STATE_PAIR_INDEX;
                        end
                    end
                end

                STATE_PAIR_INDEX:
                begin
                    if (external_input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[63:32]
                                != loaded_pair_count
                            || s_axis_tdata[31:0]
                                != expected_pair_index
                            || (
                                session_active
                                && (
                                    frame_batch_count
                                        != session_batch_count
                                    || frame_digit_count
                                        != session_digit_count
                                )
                            )
                            || pair_payload_words
                                == 64'd0
                            || pair_payload_words
                                > 64'h00000000ffffffff
                        )
                        begin
                            own_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            current_pair_index <=
                                expected_pair_index;

                            if (!session_active)
                            begin
                                session_active <=
                                    1'b1;

                                session_batch_count <=
                                    frame_batch_count;

                                session_digit_count <=
                                    frame_digit_count;
                            end

                            payload_words_remaining <=
                                pair_payload_words[31:0];

                            pair_input_complete <=
                                1'b0;

                            injection_data <= {
                                COMMAND_PROFILE,
                                COMMAND_PROFILE
                            };

                            injection_valid <=
                                1'b1;

                            injection_last <=
                                1'b0;

                            state <=
                                STATE_INJECT_PROFILE_COMMAND;
                        end
                    end
                end

                STATE_INJECT_PROFILE_COMMAND:
                begin
                    if (core_input_handshake)
                    begin
                        injection_data <=
                            profile_modulus[
                                current_pair_index
                            ];

                        state <=
                            STATE_INJECT_PROFILE_Q;
                    end
                end

                STATE_INJECT_PROFILE_Q:
                begin
                    if (core_input_handshake)
                    begin
                        injection_data <=
                            profile_mu_word[
                                current_pair_index
                            ];

                        injection_last <=
                            1'b1;

                        state <=
                            STATE_INJECT_PROFILE_MU;
                    end
                end

                STATE_INJECT_PROFILE_MU:
                begin
                    if (core_input_handshake)
                    begin
                        injection_data <= {
                            COMMAND_BATCH,
                            COMMAND_BATCH
                        };

                        injection_last <=
                            1'b0;

                        state <=
                            STATE_INJECT_BATCH_COMMAND;
                    end
                end

                STATE_INJECT_BATCH_COMMAND:
                begin
                    if (core_input_handshake)
                    begin
                        injection_data <= {
                            frame_digit_count,
                            frame_batch_count
                        };

                        state <=
                            STATE_INJECT_BATCH_COUNT;
                    end
                end

                STATE_INJECT_BATCH_COUNT:
                begin
                    if (core_input_handshake)
                    begin
                        injection_valid <=
                            1'b0;

                        state <=
                            STATE_FORWARD_PAIR_DATA;
                    end
                end

                STATE_FORWARD_PAIR_DATA:
                begin
                    if (payload_enqueue)
                    begin
                        if (
                            s_axis_tlast
                                != payload_final_word
                        )
                        begin
                            own_protocol_error <=
                                1'b1;
                        end

                        if (payload_final_word)
                        begin
                            pair_input_complete <=
                                1'b1;
                        end
                        else
                        begin
                            payload_words_remaining <=
                                payload_words_remaining
                                - 1'b1;
                        end
                    end

                    if (
                        payload_dequeue
                        && payload_head_last
                    )
                    begin
                        state <=
                            STATE_WAIT_PAIR_OUTPUT;
                    end
                end

                STATE_WAIT_PAIR_OUTPUT:
                begin
                    if (pair_output_complete)
                    begin
                        completed_pairs <=
                            completed_pairs
                            + 1'b1;

                        if (final_pair)
                        begin
                            completed_ciphertexts <=
                                completed_ciphertexts
                                + session_batch_count;

                            completed_batches <=
                                completed_batches
                                + 1'b1;

                            session_active <=
                                1'b0;

                            expected_pair_index <=
                                '0;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            expected_pair_index <=
                                expected_pair_index
                                + 1'b1;

                            state <=
                                STATE_IDLE;
                        end
                    end
                end

                STATE_DISCARD:
                begin
                    injection_valid <=
                        1'b0;

                    injection_last <=
                        1'b0;

                    if (
                        external_input_handshake
                        && s_axis_tlast
                    )
                    begin
                        session_active <=
                            1'b0;

                        expected_pair_index <=
                            '0;

                        state <=
                            STATE_IDLE;
                    end
                end

                default:
                begin
                    session_active <=
                        1'b0;

                    expected_pair_index <=
                        '0;

                    state <=
                        STATE_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            payload_write_pointer <=
                1'b0;

            payload_read_pointer <=
                1'b0;

            payload_count <=
                2'd0;

            payload_data[0] <=
                64'd0;

            payload_data[1] <=
                64'd0;

            payload_last[0] <=
                1'b0;

            payload_last[1] <=
                1'b0;
        end
        else
        begin
            case ({
                payload_enqueue,
                payload_dequeue
            })
                2'b10:
                payload_count <=
                    payload_count
                    + 1'b1;

                2'b01:
                payload_count <=
                    payload_count
                    - 1'b1;

                default:
                begin
                end
            endcase

            if (payload_enqueue)
            begin
                payload_data[
                    payload_write_pointer
                ] <= s_axis_tdata;

                payload_last[
                    payload_write_pointer
                ] <= payload_final_word;

                payload_write_pointer <=
                    payload_write_pointer
                    + 1'b1;
            end

            if (payload_dequeue)
            begin
                payload_read_pointer <=
                    payload_read_pointer
                    + 1'b1;
            end
        end
    end

    evalmul3_bv_keyreuse_drain_overlap_axis_core #(
        .N               (N),
        .MAX_BATCH       (MAX_BATCH),
        .MIN_BATCH       (MIN_BATCH),
        .MAX_DIGITS      (MAX_DIGITS),
        .EVAL_META_DEPTH (EVAL_META_DEPTH),
        .BV_META_DEPTH   (BV_META_DEPTH)
    ) core (
        .clk                    (clk),
        .reset_n                (reset_n),

        .s_axis_tdata           (core_s_axis_tdata),
        .s_axis_tvalid          (core_s_axis_tvalid),
        .s_axis_tready          (core_s_axis_tready),
        .s_axis_tlast           (core_s_axis_tlast),

        .m_axis_tdata           (core_m_axis_tdata),
        .m_axis_tvalid          (core_m_axis_tvalid),
        .m_axis_tready          (core_m_axis_tready),
        .m_axis_tlast           (core_m_axis_tlast),

        .protocol_error         (core_protocol_error),
        .profile_ready          (core_profile_ready),
        .accelerator_busy       (core_accelerator_busy),

        .active_modulus         (core_active_modulus),
        .active_modulus_mu      (core_active_modulus_mu),
        .active_batch_size      (core_active_batch_size),
        .active_digit_count     (core_active_digit_count),

        .completed_profiles     (core_completed_profiles),
        .completed_ciphertexts  (core_completed_ciphertexts),
        .completed_batches      (core_completed_batches),
        .completed_coefficients (core_completed_coefficients)
    );

`ifndef SYNTHESIS

    initial
    begin
        if (
            N <= 0
            || (
                N
                & (
                    N
                    - 1
                )
            ) != 0
        )
        begin
            $display(
                "ERROR: multi-pair session N must be a positive power of two"
            );

            $fatal(1);
        end

        if (
            MAX_BATCH > 64
            || MAX_DIGITS > 16
        )
        begin
            $display(
                "ERROR: no-DSP length arithmetic assumes MAX_BATCH<=64 and MAX_DIGITS<=16"
            );

            $fatal(1);
        end
    end

    localparam logic [63:0] BARRETT_SCALE =
        64'h1000000000000000;

    always @(posedge clk)
    begin
        if (
            reset_n
            && state == STATE_PROFILE_MU
            && external_input_handshake
            && s_axis_tlast == final_profile_word
            && !s_axis_tdata[31]
            && !s_axis_tdata[63]
        )
        begin
            if (
                s_axis_tdata[30:0]
                    != BARRETT_SCALE
                        / profile_modulus[
                            profile_write_index
                        ][31:0]
                || s_axis_tdata[62:32]
                    != BARRETT_SCALE
                        / profile_modulus[
                            profile_write_index
                        ][63:32]
            )
            begin
                $display(
                    "ERROR: RLPT Barrett reciprocal does not match modulus"
                );

                $fatal(1);
            end
        end

        if (
            reset_n
            && payload_enqueue
            && payload_words_remaining
                == 32'd0
        )
        begin
            $display(
                "ERROR: accepted payload after pair frame was complete"
            );

            $fatal(1);
        end

        if (
            reset_n
            && pair_output_complete
            && !session_active
        )
        begin
            $display(
                "ERROR: pair output completed outside an active session"
            );

            $fatal(1);
        end

        if (
            reset_n
            && core_m_axis_tlast
            && core_m_axis_tvalid
            && !final_pair
            && m_axis_tlast
        )
        begin
            $display(
                "ERROR: intermediate child TLAST leaked externally"
            );

            $fatal(1);
        end
    end

`endif

endmodule
