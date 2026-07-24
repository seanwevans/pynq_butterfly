`timescale 1ns/1ps

/*
 * Multi-pair transaction sequencer for evalmul3_two_tower_axis_core.
 *
 * The arithmetic core still processes one pair of RNS towers at a time. This
 * module stores a table of paired-tower Barrett profiles and turns one external
 * all-pair frame into the sequence of EVPF/EVB3 frames expected by the proven
 * two-tower core.
 *
 * Profile-table frame:
 *
 *     word 0: { "EVPT", "EVPT" }
 *     word 1: { pair_count, pair_count }
 *
 *     repeated pair_count times:
 *
 *         { q1,  q0  }
 *         { mu1, mu0 }
 *
 *     TLAST is asserted only on the final mu word.
 *
 * All-pair batch frame:
 *
 *     word 0: { "EV12", "EV12" }
 *     word 1: { pair_count, ciphertext_count }
 *
 *     repeated pair_count times, pair-major:
 *
 *         for each ciphertext and coefficient:
 *
 *             a0
 *             a1
 *             b0
 *             b1
 *
 *     TLAST is asserted only on the final b1 word of the final pair.
 *
 * Output is pair-major c0/c1/c2 data. Intermediate two-tower TLAST markers are
 * suppressed. Only the final c2 word of the final pair carries external TLAST.
 */
module evalmul3_all_tower_axis_core #(
    parameter integer N = 4096,
    parameter integer FIFO_DEPTH = 8,
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
    output logic [31:0] completed_profiles,
    output logic [31:0] completed_ciphertexts,
    output logic [31:0] completed_batches,
    output logic [31:0] launched_coefficients
);

    localparam integer INDEX_WIDTH =
        (N <= 2) ? 1 : $clog2(N);

    localparam integer PAIR_INDEX_WIDTH =
        (MAX_PAIR_COUNT <= 2) ? 1 : $clog2(MAX_PAIR_COUNT);

    localparam logic [INDEX_WIDTH-1:0] LAST_COEFFICIENT =
        N - 1;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h45565046;  // "EVPF"

    localparam logic [31:0] COMMAND_BATCH =
        32'h45564233;  // "EVB3"

    localparam logic [31:0] COMMAND_PROFILE_TABLE =
        32'h45565054;  // "EVPT"

    localparam logic [31:0] COMMAND_ALL_PAIRS =
        32'h45563132;  // "EV12"

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PROFILE_COUNT,
        STATE_PROFILE_Q,
        STATE_PROFILE_MU,
        STATE_BATCH_HEADER,
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
    logic [31:0] active_pair_count;

    logic [PAIR_INDEX_WIDTH-1:0] profile_write_index;
    logic [PAIR_INDEX_WIDTH-1:0] current_pair_index;

    logic profile_table_ready;

    logic [31:0] batch_count;
    logic [31:0] input_ciphertext_index;
    logic [INDEX_WIDTH-1:0] input_coefficient_index;
    logic [1:0] input_operand_phase;

    /*
     * Two-word registered payload FIFO between the external EV12 stream and
     * the legacy two-tower core.
     *
     * This removes the direct child-ready -> external-ready combinational path
     * when STATE_FORWARD_PAIR_DATA begins. A depth of two still sustains one
     * word per clock: after the first fill, enqueue and dequeue can occur
     * together on every cycle.
     */
    logic [63:0] payload_data [0:1];
    logic        payload_last [0:1];
    logic        payload_write_pointer;
    logic        payload_read_pointer;
    logic [1:0]  payload_count;
    logic        pair_input_complete;

    logic own_protocol_error;

    wire external_input_handshake =
        s_axis_tvalid
        && s_axis_tready;

    wire payload_enqueue =
        state == STATE_FORWARD_PAIR_DATA
        && external_input_handshake;

    wire payload_dequeue =
        state == STATE_FORWARD_PAIR_DATA
        && payload_count != 0
        && core_s_axis_tready;

    wire payload_head_last =
        payload_last[payload_read_pointer];

    wire profile_table_command =
        s_axis_tdata == {
            COMMAND_PROFILE_TABLE,
            COMMAND_PROFILE_TABLE
        };

    wire all_pairs_command =
        s_axis_tdata == {
            COMMAND_ALL_PAIRS,
            COMMAND_ALL_PAIRS
        };

    wire pair_data_final_word =
        input_operand_phase == 2'd3
        && input_coefficient_index == LAST_COEFFICIENT
        && input_ciphertext_index + 1'b1 == batch_count;

    wire final_pair =
        current_pair_index + 1'b1 == active_pair_count;

    wire global_input_final_word =
        pair_data_final_word
        && final_pair;

    wire final_profile_word =
        profile_write_index + 1'b1 == loading_pair_count;

    /*
     * Proven two-tower core interface.
     */
    logic [63:0] core_s_axis_tdata;
    logic        core_s_axis_tvalid;
    wire         core_s_axis_tready;
    logic        core_s_axis_tlast;

    /*
     * Internally generated legacy EVPF/EVB3 words are held in a registered
     * one-word source. This deliberately breaks the state -> TVALID ->
     * child-ready delta-cycle path that caused Icarus to oscillate when the
     * sequencer entered STATE_INJECT_PROFILE_COMMAND.
     */
    logic [63:0] injection_data;
    logic        injection_valid;
    logic        injection_last;

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
    wire [31:0]  core_completed_profiles;
    wire [31:0]  core_completed_ciphertexts;
    wire [31:0]  core_completed_batches;
    wire [31:0]  core_launched_coefficients;

    wire core_input_handshake =
        core_s_axis_tvalid
        && core_s_axis_tready;

    wire core_output_handshake =
        core_m_axis_tvalid
        && core_m_axis_tready;

    wire pair_output_complete =
        core_output_handshake
        && core_m_axis_tlast;

    assign protocol_error =
        own_protocol_error
        || core_protocol_error;

    assign profile_ready =
        profile_table_ready;

    assign accelerator_busy =
        state != STATE_IDLE
        || core_accelerator_busy;

    assign active_modulus =
        core_active_modulus;

    assign active_modulus_mu =
        core_active_modulus_mu;

    assign launched_coefficients =
        core_launched_coefficients;

    /*
     * External output is the two-tower output stream with intermediate TLAST
     * markers suppressed.
     */
    always_comb
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
     * External input arbitration.
     *
     * Internal EVPF/EVB3 headers come from the registered injection source.
     * Payload words are forwarded directly only in STATE_FORWARD_PAIR_DATA.
     */
    always_comb
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
            STATE_BATCH_HEADER,
            STATE_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            STATE_FORWARD_PAIR_DATA:
            begin
                core_s_axis_tdata =
                    payload_data[payload_read_pointer];

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

            active_pair_count <=
                32'd0;

            profile_write_index <=
                '0;

            current_pair_index <=
                '0;

            profile_table_ready <=
                1'b0;

            batch_count <=
                32'd0;

            active_batch_size <=
                32'd0;

            input_ciphertext_index <=
                32'd0;

            input_coefficient_index <=
                '0;

            input_operand_phase <=
                2'd0;

            injection_data <=
                64'd0;

            injection_valid <=
                1'b0;

            injection_last <=
                1'b0;

            pair_input_complete <=
                1'b0;

            own_protocol_error <=
                1'b0;

            completed_profiles <=
                32'd0;

            completed_ciphertexts <=
                32'd0;

            completed_batches <=
                32'd0;

            for (
                reset_index = 0;
                reset_index < MAX_PAIR_COUNT;
                reset_index = reset_index + 1
            )
            begin
                profile_modulus[reset_index] <=
                    64'd0;

                profile_mu_word[reset_index] <=
                    64'd0;
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
                        else if (profile_table_command)
                        begin
                            state <=
                                STATE_PROFILE_COUNT;
                        end
                        else if (
                            all_pairs_command
                            && profile_table_ready
                        )
                        begin
                            state <=
                                STATE_BATCH_HEADER;
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
                            || s_axis_tdata[31:0] == 32'd0
                            || s_axis_tdata[63:32]
                                != s_axis_tdata[31:0]
                            || s_axis_tdata[31:0] > MAX_PAIR_COUNT
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
                            || s_axis_tdata[31:30] != 2'b00
                            || s_axis_tdata[63:62] != 2'b00
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
                            ] <=
                                s_axis_tdata;

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
                            s_axis_tlast != final_profile_word
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
                            ] <=
                                s_axis_tdata;

                            if (final_profile_word)
                            begin
                                loaded_pair_count <=
                                    loading_pair_count;

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
                                    profile_write_index + 1'b1;

                                state <=
                                    STATE_PROFILE_Q;
                            end
                        end
                    end
                end

                STATE_BATCH_HEADER:
                begin
                    if (external_input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:0] == 32'd0
                            || s_axis_tdata[63:32] == 32'd0
                            || s_axis_tdata[63:32]
                                != loaded_pair_count
                            || s_axis_tdata[63:32] > MAX_PAIR_COUNT
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
                            batch_count <=
                                s_axis_tdata[31:0];

                            active_batch_size <=
                                s_axis_tdata[31:0];

                            active_pair_count <=
                                s_axis_tdata[63:32];

                            current_pair_index <=
                                '0;

                            input_ciphertext_index <=
                                32'd0;

                            input_coefficient_index <=
                                '0;

                            input_operand_phase <=
                                2'd0;

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
                            profile_modulus[current_pair_index];

                        injection_last <=
                            1'b0;

                        state <=
                            STATE_INJECT_PROFILE_Q;
                    end
                end

                STATE_INJECT_PROFILE_Q:
                begin
                    if (core_input_handshake)
                    begin
                        injection_data <=
                            profile_mu_word[current_pair_index];

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
                            batch_count,
                            batch_count
                        };

                        injection_last <=
                            1'b0;

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

                        injection_last <=
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
                            != global_input_final_word
                        )
                        begin
                            own_protocol_error <=
                                1'b1;
                        end

                        if (pair_data_final_word)
                        begin
                            pair_input_complete <=
                                1'b1;

                            input_ciphertext_index <=
                                32'd0;

                            input_coefficient_index <=
                                '0;

                            input_operand_phase <=
                                2'd0;
                        end
                        else if (input_operand_phase != 2'd3)
                        begin
                            input_operand_phase <=
                                input_operand_phase + 1'b1;
                        end
                        else
                        begin
                            input_operand_phase <=
                                2'd0;

                            if (
                                input_coefficient_index
                                == LAST_COEFFICIENT
                            )
                            begin
                                input_coefficient_index <=
                                    '0;

                                input_ciphertext_index <=
                                    input_ciphertext_index + 1'b1;
                            end
                            else
                            begin
                                input_coefficient_index <=
                                    input_coefficient_index + 1'b1;
                            end
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
                        if (final_pair)
                        begin
                            completed_ciphertexts <=
                                completed_ciphertexts
                                + batch_count;

                            completed_batches <=
                                completed_batches + 1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            current_pair_index <=
                                current_pair_index + 1'b1;

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
                        state <=
                            STATE_IDLE;
                    end
                end

                default:
                begin
                    state <=
                        STATE_IDLE;
                end
            endcase
        end
    end

    /*
     * Registered two-entry payload FIFO.
     *
     * Count changes only on unmatched enqueue/dequeue. Simultaneous transfer
     * advances both pointers while preserving occupancy, sustaining one word
     * per cycle without a combinational ready path through the child core.
     */
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
                begin
                    payload_count <=
                        payload_count + 1'b1;
                end

                2'b01:
                begin
                    payload_count <=
                        payload_count - 1'b1;
                end

                default:
                begin
                end
            endcase

            if (payload_enqueue)
            begin
                payload_data[payload_write_pointer] <=
                    s_axis_tdata;

                payload_last[payload_write_pointer] <=
                    pair_data_final_word;

                payload_write_pointer <=
                    payload_write_pointer + 1'b1;
            end

            if (payload_dequeue)
            begin
                payload_read_pointer <=
                    payload_read_pointer + 1'b1;
            end
        end
    end

    evalmul3_two_tower_axis_core #(
        .N          (N),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) two_tower_core (
        .clk                   (clk),
        .reset_n               (reset_n),

        .s_axis_tdata          (core_s_axis_tdata),
        .s_axis_tvalid         (core_s_axis_tvalid),
        .s_axis_tready         (core_s_axis_tready),
        .s_axis_tlast          (core_s_axis_tlast),

        .m_axis_tdata          (core_m_axis_tdata),
        .m_axis_tvalid         (core_m_axis_tvalid),
        .m_axis_tready         (core_m_axis_tready),
        .m_axis_tlast          (core_m_axis_tlast),

        .protocol_error        (core_protocol_error),
        .profile_ready         (core_profile_ready),
        .accelerator_busy      (core_accelerator_busy),

        .active_modulus        (core_active_modulus),
        .active_modulus_mu     (core_active_modulus_mu),

        .active_batch_size     (core_active_batch_size),
        .completed_profiles    (core_completed_profiles),
        .completed_ciphertexts (core_completed_ciphertexts),
        .completed_batches     (core_completed_batches),
        .launched_coefficients (core_launched_coefficients)
    );

`ifndef SYNTHESIS

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
                    "ERROR: incorrect all-pair profile reciprocal at pair %0d",
                    profile_write_index
                );

                $fatal(1);
            end
        end

        if (
            reset_n
            && payload_enqueue
            && payload_count == 2
        )
        begin
            $display(
                "ERROR: all-pair payload FIFO overflow"
            );

            $fatal(1);
        end

        if (
            reset_n
            && payload_dequeue
            && payload_count == 0
        )
        begin
            $display(
                "ERROR: all-pair payload FIFO underflow"
            );

            $fatal(1);
        end

        if (
            reset_n
            && state == STATE_WAIT_PAIR_OUTPUT
            && payload_count != 0
        )
        begin
            $display(
                "ERROR: entered pair-output wait with buffered payload remaining"
            );

            $fatal(1);
        end

        if (
            reset_n
            && state == STATE_WAIT_PAIR_OUTPUT
            && pair_output_complete
            && core_protocol_error
        )
        begin
            $display(
                "ERROR: internally generated EVPF/EVB3 frame failed"
            );

            $fatal(1);
        end
    end

    initial
    begin
        if (N < 2 || (N & (N - 1)) != 0)
        begin
            $display(
                "ERROR: all-pair evalmul3 requires power-of-two N >= 2"
            );

            $fatal(1);
        end

        if (MAX_PAIR_COUNT < 1)
        begin
            $display(
                "ERROR: MAX_PAIR_COUNT must be positive"
            );

            $fatal(1);
        end
    end

`endif

endmodule
