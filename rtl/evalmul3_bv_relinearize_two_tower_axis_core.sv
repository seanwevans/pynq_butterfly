`timescale 1ns/1ps

/*
 * Exact two-tower EvalMul3 plus host-decomposed OpenFHE BV relinearization.
 *
 * External profile:
 *
 *     word 0: { "RLPF", "RLPF" }
 *     word 1: { q1, q0 }
 *     word 2: { mu1, mu0 }, TLAST
 *
 * External batch:
 *
 *     word 0: { "RLBV", "RLBV" }
 *     word 1: { digit_count, ciphertext_count }
 *
 * For each ciphertext and coefficient:
 *
 *     a0
 *     a1
 *     b0
 *     b1
 *
 *     for each BV digit:
 *         digit
 *         eval_key_b
 *         eval_key_a
 *
 * Output:
 *
 *     relin_c0 = c0 + ks_b mod q
 *     relin_c1 = c1 + ks_a mod q
 *
 * This checkpoint fuses the exact 128-DSP EvalMul3 engine, the exact 64-DSP
 * BV evaluation-key MAC, and the final modular additions. BV decomposition is
 * supplied by the host and remains outside the FPGA.
 */
module evalmul3_bv_relinearize_two_tower_axis_core #(
    parameter integer N = 4096,
    parameter integer MAX_DIGITS = 16,
    parameter integer INNER_FIFO_DEPTH = 8,
    parameter integer ALIGN_FIFO_DEPTH = 8
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
    output logic [31:0] completed_coefficients
);

    localparam integer INDEX_WIDTH =
        (N <= 2) ? 1 : $clog2(N);

    localparam integer DIGIT_WIDTH =
        (MAX_DIGITS <= 1)
        ? 1
        : $clog2(MAX_DIGITS + 1);

    localparam integer FIFO_PTR_WIDTH =
        (ALIGN_FIFO_DEPTH <= 2)
        ? 1
        : $clog2(ALIGN_FIFO_DEPTH);

    localparam logic [INDEX_WIDTH-1:0] LAST_COEFFICIENT =
        N - 1;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h524c5046;  // "RLPF"

    localparam logic [31:0] COMMAND_BATCH =
        32'h524c4256;  // "RLBV"

    localparam logic [31:0] COMMAND_EVAL_PROFILE =
        32'h45565046;  // "EVPF"

    localparam logic [31:0] COMMAND_EVAL_BATCH =
        32'h45564233;  // "EVB3"

    localparam logic [31:0] COMMAND_BV_PROFILE =
        32'h42565046;  // "BVPF"

    localparam logic [31:0] COMMAND_BV_BATCH =
        32'h42564b4d;  // "BVKM"

    typedef enum logic [4:0] {
        STATE_IDLE,
        STATE_PROFILE_Q,
        STATE_PROFILE_MU,

        STATE_INJECT_EVAL_PROFILE_COMMAND,
        STATE_INJECT_EVAL_PROFILE_Q,
        STATE_INJECT_EVAL_PROFILE_MU,

        STATE_INJECT_BV_PROFILE_COMMAND,
        STATE_INJECT_BV_PROFILE_Q,
        STATE_INJECT_BV_PROFILE_MU,

        STATE_BATCH_HEADER,

        STATE_INJECT_EVAL_BATCH_COMMAND,
        STATE_INJECT_EVAL_BATCH_COUNT,

        STATE_INJECT_BV_BATCH_COMMAND,
        STATE_INJECT_BV_BATCH_HEADER,

        STATE_PAYLOAD,
        STATE_WAIT_COMPLETE,
        STATE_DISCARD
    } state_t;

    state_t state;

    logic wrapper_protocol_error;

    logic [63:0] modulus_word;
    logic [63:0] mu_word;

    logic [31:0] batch_count;
    logic [31:0] digit_count;

    logic [31:0] input_ciphertext_index;
    logic [INDEX_WIDTH-1:0] input_coefficient_index;

    logic input_eval_section;
    logic [1:0] input_eval_phase;
    logic [DIGIT_WIDTH-1:0] input_bv_digit_index;
    logic [1:0] input_bv_phase;

    assign active_modulus =
        modulus_word;

    assign active_modulus_mu = {
        mu_word[62:32],
        mu_word[30:0]
    };

    wire external_handshake =
        s_axis_tvalid
        && s_axis_tready;

    wire external_profile_command =
        s_axis_tdata == {
            COMMAND_PROFILE,
            COMMAND_PROFILE
        };

    wire external_batch_command =
        s_axis_tdata == {
            COMMAND_BATCH,
            COMMAND_BATCH
        };

    wire final_ciphertext =
        input_ciphertext_index + 1'b1
        == batch_count;

    wire final_coefficient =
        input_coefficient_index
        == LAST_COEFFICIENT;

    wire final_eval_payload_word =
        state == STATE_PAYLOAD
        && input_eval_section
        && input_eval_phase == 2'd3
        && final_coefficient
        && final_ciphertext;

    wire final_bv_digit =
        input_bv_digit_index + 1'b1
        == digit_count;

    wire final_external_payload_word =
        state == STATE_PAYLOAD
        && !input_eval_section
        && input_bv_phase == 2'd2
        && final_bv_digit
        && final_coefficient
        && final_ciphertext;

    /*
     * Inner EvalMul3 stream.
     */
    logic [63:0] eval_s_axis_tdata;
    logic        eval_s_axis_tvalid;
    wire         eval_s_axis_tready;
    logic        eval_s_axis_tlast;

    wire [63:0]  eval_m_axis_tdata;
    wire         eval_m_axis_tvalid;
    logic        eval_m_axis_tready;
    wire         eval_m_axis_tlast;

    wire eval_protocol_error;
    wire eval_profile_ready;
    wire eval_busy;

    /*
     * Inner BV-MAC stream.
     */
    logic [63:0] bv_s_axis_tdata;
    logic        bv_s_axis_tvalid;
    wire         bv_s_axis_tready;
    logic        bv_s_axis_tlast;

    wire [63:0]  bv_m_axis_tdata;
    wire         bv_m_axis_tvalid;
    logic        bv_m_axis_tready;
    wire         bv_m_axis_tlast;

    wire bv_protocol_error;
    wire bv_profile_ready;
    wire bv_busy;

    wire eval_input_handshake =
        eval_s_axis_tvalid
        && eval_s_axis_tready;

    wire bv_input_handshake =
        bv_s_axis_tvalid
        && bv_s_axis_tready;

    always @*
    begin
        s_axis_tready =
            1'b0;

        eval_s_axis_tdata =
            64'd0;

        eval_s_axis_tvalid =
            1'b0;

        eval_s_axis_tlast =
            1'b0;

        bv_s_axis_tdata =
            64'd0;

        bv_s_axis_tvalid =
            1'b0;

        bv_s_axis_tlast =
            1'b0;

        case (state)
            STATE_IDLE,
            STATE_PROFILE_Q,
            STATE_PROFILE_MU,
            STATE_BATCH_HEADER,
            STATE_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            STATE_INJECT_EVAL_PROFILE_COMMAND:
            begin
                eval_s_axis_tdata = {
                    COMMAND_EVAL_PROFILE,
                    COMMAND_EVAL_PROFILE
                };

                eval_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_EVAL_PROFILE_Q:
            begin
                eval_s_axis_tdata =
                    modulus_word;

                eval_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_EVAL_PROFILE_MU:
            begin
                eval_s_axis_tdata =
                    mu_word;

                eval_s_axis_tvalid =
                    1'b1;

                eval_s_axis_tlast =
                    1'b1;
            end

            STATE_INJECT_BV_PROFILE_COMMAND:
            begin
                bv_s_axis_tdata = {
                    COMMAND_BV_PROFILE,
                    COMMAND_BV_PROFILE
                };

                bv_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_BV_PROFILE_Q:
            begin
                bv_s_axis_tdata =
                    modulus_word;

                bv_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_BV_PROFILE_MU:
            begin
                bv_s_axis_tdata =
                    mu_word;

                bv_s_axis_tvalid =
                    1'b1;

                bv_s_axis_tlast =
                    1'b1;
            end

            STATE_INJECT_EVAL_BATCH_COMMAND:
            begin
                eval_s_axis_tdata = {
                    COMMAND_EVAL_BATCH,
                    COMMAND_EVAL_BATCH
                };

                eval_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_EVAL_BATCH_COUNT:
            begin
                eval_s_axis_tdata = {
                    batch_count,
                    batch_count
                };

                eval_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_BV_BATCH_COMMAND:
            begin
                bv_s_axis_tdata = {
                    COMMAND_BV_BATCH,
                    COMMAND_BV_BATCH
                };

                bv_s_axis_tvalid =
                    1'b1;
            end

            STATE_INJECT_BV_BATCH_HEADER:
            begin
                bv_s_axis_tdata = {
                    digit_count,
                    batch_count
                };

                bv_s_axis_tvalid =
                    1'b1;
            end

            STATE_PAYLOAD:
            begin
                if (input_eval_section)
                begin
                    eval_s_axis_tdata =
                        s_axis_tdata;

                    eval_s_axis_tvalid =
                        s_axis_tvalid;

                    eval_s_axis_tlast =
                        final_eval_payload_word;

                    s_axis_tready =
                        eval_s_axis_tready;
                end
                else
                begin
                    bv_s_axis_tdata =
                        s_axis_tdata;

                    bv_s_axis_tvalid =
                        s_axis_tvalid;

                    bv_s_axis_tlast =
                        final_external_payload_word;

                    s_axis_tready =
                        bv_s_axis_tready;
                end
            end

            default:
            begin
            end
        endcase
    end

    evalmul3_two_tower_axis_core #(
        .N          (N),
        .FIFO_DEPTH (INNER_FIFO_DEPTH)
    ) evalmul_engine (
        .clk                   (clk),
        .reset_n               (reset_n),

        .s_axis_tdata          (eval_s_axis_tdata),
        .s_axis_tvalid         (eval_s_axis_tvalid),
        .s_axis_tready         (eval_s_axis_tready),
        .s_axis_tlast          (eval_s_axis_tlast),

        .m_axis_tdata          (eval_m_axis_tdata),
        .m_axis_tvalid         (eval_m_axis_tvalid),
        .m_axis_tready         (eval_m_axis_tready),
        .m_axis_tlast          (eval_m_axis_tlast),

        .protocol_error        (eval_protocol_error),
        .profile_ready         (eval_profile_ready),
        .accelerator_busy      (eval_busy),

        .active_modulus        (),
        .active_modulus_mu     (),
        .active_batch_size     (),
        .completed_profiles    (),
        .completed_ciphertexts (),
        .completed_batches     (),
        .launched_coefficients ()
    );

    bv_keyswitch_mac_two_tower_axis_core #(
        .N          (N),
        .MAX_DIGITS (MAX_DIGITS),
        .FIFO_DEPTH (INNER_FIFO_DEPTH)
    ) bv_mac_engine (
        .clk                     (clk),
        .reset_n                 (reset_n),

        .s_axis_tdata            (bv_s_axis_tdata),
        .s_axis_tvalid           (bv_s_axis_tvalid),
        .s_axis_tready           (bv_s_axis_tready),
        .s_axis_tlast            (bv_s_axis_tlast),

        .m_axis_tdata            (bv_m_axis_tdata),
        .m_axis_tvalid           (bv_m_axis_tvalid),
        .m_axis_tready           (bv_m_axis_tready),
        .m_axis_tlast            (bv_m_axis_tlast),

        .protocol_error          (bv_protocol_error),
        .profile_ready           (bv_profile_ready),
        .accelerator_busy        (bv_busy),

        .active_modulus          (),
        .active_modulus_mu       (),
        .active_batch_size       (),
        .active_digit_count      (),
        .completed_profiles      (),
        .completed_ciphertexts   (),
        .completed_batches       (),
        .launched_digit_products (),
        .completed_coefficients  ()
    );

    assign protocol_error =
        wrapper_protocol_error
        || eval_protocol_error
        || bv_protocol_error;

    /*
     * Capture c0/c1 and consume c2 from EvalMul3.
     */
    logic [1:0] eval_capture_component;
    logic [63:0] eval_capture_c0;
    logic [63:0] eval_capture_c1;

    logic [63:0] eval_fifo_c0 [0:ALIGN_FIFO_DEPTH-1];
    logic [63:0] eval_fifo_c1 [0:ALIGN_FIFO_DEPTH-1];

    logic [FIFO_PTR_WIDTH-1:0] eval_fifo_write_pointer;
    logic [FIFO_PTR_WIDTH-1:0] eval_fifo_read_pointer;
    logic [FIFO_PTR_WIDTH:0]   eval_fifo_count;

    /*
     * Capture ks_b/ks_a from the BV MAC.
     */
    logic bv_capture_component;
    logic [63:0] bv_capture_ks_b;

    logic [63:0] bv_fifo_ks_b [0:ALIGN_FIFO_DEPTH-1];
    logic [63:0] bv_fifo_ks_a [0:ALIGN_FIFO_DEPTH-1];

    logic [FIFO_PTR_WIDTH-1:0] bv_fifo_write_pointer;
    logic [FIFO_PTR_WIDTH-1:0] bv_fifo_read_pointer;
    logic [FIFO_PTR_WIDTH:0]   bv_fifo_count;

    wire eval_fifo_has_credit =
        eval_fifo_count < ALIGN_FIFO_DEPTH;

    wire bv_fifo_has_credit =
        bv_fifo_count < ALIGN_FIFO_DEPTH;

    assign eval_m_axis_tready =
        eval_capture_component != 2'd0
        || eval_fifo_has_credit;

    assign bv_m_axis_tready =
        bv_capture_component
        || bv_fifo_has_credit;

    wire eval_output_handshake =
        eval_m_axis_tvalid
        && eval_m_axis_tready;

    wire bv_output_handshake =
        bv_m_axis_tvalid
        && bv_m_axis_tready;

    wire eval_fifo_push =
        eval_output_handshake
        && eval_capture_component == 2'd2;

    wire bv_fifo_push =
        bv_output_handshake
        && bv_capture_component;

    /*
     * Final modular additions.
     */
    /*
     * Icarus expands constant selects inside always @* sensitivity lists.
     * With dynamically indexed FIFO memories, that can create pathological
     * delta-cycle churn before the first real clock edge. Keep this purely
     * combinational datapath as continuous assignments instead.
     */
    wire [63:0] eval_head_c0 =
        !reset_n || eval_fifo_count == 0
        ? 64'd0
        : eval_fifo_c0[
            eval_fifo_read_pointer
        ];

    wire [63:0] eval_head_c1 =
        !reset_n || eval_fifo_count == 0
        ? 64'd0
        : eval_fifo_c1[
            eval_fifo_read_pointer
        ];

    wire [63:0] bv_head_ks_b =
        !reset_n || bv_fifo_count == 0
        ? 64'd0
        : bv_fifo_ks_b[
            bv_fifo_read_pointer
        ];

    wire [63:0] bv_head_ks_a =
        !reset_n || bv_fifo_count == 0
        ? 64'd0
        : bv_fifo_ks_a[
            bv_fifo_read_pointer
        ];

    wire [32:0] relin_c0_sum_lane0 = {
        1'b0,
        eval_head_c0[31:0]
    } + {
        1'b0,
        bv_head_ks_b[31:0]
    };

    wire [32:0] relin_c0_sum_lane1 = {
        1'b0,
        eval_head_c0[63:32]
    } + {
        1'b0,
        bv_head_ks_b[63:32]
    };

    wire [32:0] relin_c1_sum_lane0 = {
        1'b0,
        eval_head_c1[31:0]
    } + {
        1'b0,
        bv_head_ks_a[31:0]
    };

    wire [32:0] relin_c1_sum_lane1 = {
        1'b0,
        eval_head_c1[63:32]
    } + {
        1'b0,
        bv_head_ks_a[63:32]
    };

    wire [31:0] relin_c0_lane0 =
        relin_c0_sum_lane0
            >= {
                1'b0,
                modulus_word[31:0]
            }
        ? relin_c0_sum_lane0[31:0]
            - modulus_word[31:0]
        : relin_c0_sum_lane0[31:0];

    wire [31:0] relin_c0_lane1 =
        relin_c0_sum_lane1
            >= {
                1'b0,
                modulus_word[63:32]
            }
        ? relin_c0_sum_lane1[31:0]
            - modulus_word[63:32]
        : relin_c0_sum_lane1[31:0];

    wire [31:0] relin_c1_lane0 =
        relin_c1_sum_lane0
            >= {
                1'b0,
                modulus_word[31:0]
            }
        ? relin_c1_sum_lane0[31:0]
            - modulus_word[31:0]
        : relin_c1_sum_lane0[31:0];

    wire [31:0] relin_c1_lane1 =
        relin_c1_sum_lane1
            >= {
                1'b0,
                modulus_word[63:32]
            }
        ? relin_c1_sum_lane1[31:0]
            - modulus_word[63:32]
        : relin_c1_sum_lane1[31:0];

    logic output_component;
    logic [31:0] output_ciphertext_index;
    logic [INDEX_WIDTH-1:0] output_coefficient_index;

    assign m_axis_tvalid =
        eval_fifo_count != 0
        && bv_fifo_count != 0;

    assign m_axis_tdata =
        output_component
        ? {
            relin_c1_lane1,
            relin_c1_lane0
        }
        : {
            relin_c0_lane1,
            relin_c0_lane0
        };

    wire final_output_word =
        output_component
        && output_coefficient_index == LAST_COEFFICIENT
        && output_ciphertext_index + 1'b1 == batch_count;

    assign m_axis_tlast =
        m_axis_tvalid
        && final_output_word;

    wire output_handshake =
        m_axis_tvalid
        && m_axis_tready;

    wire release_aligned_entry =
        output_handshake
        && output_component;

    wire batch_output_complete =
        release_aligned_entry
        && final_output_word;

    assign accelerator_busy =
        state != STATE_IDLE
        || eval_busy
        || bv_busy
        || eval_fifo_count != 0
        || bv_fifo_count != 0;

    /*
     * External protocol, injection, and payload routing.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            wrapper_protocol_error <=
                1'b0;

            modulus_word <=
                64'd0;

            mu_word <=
                64'd0;

            batch_count <=
                32'd0;

            digit_count <=
                32'd0;

            active_batch_size <=
                32'd0;

            active_digit_count <=
                32'd0;

            input_ciphertext_index <=
                32'd0;

            input_coefficient_index <=
                '0;

            input_eval_section <=
                1'b1;

            input_eval_phase <=
                2'd0;

            input_bv_digit_index <=
                '0;

            input_bv_phase <=
                2'd0;

            profile_ready <=
                1'b0;

            completed_profiles <=
                32'd0;
        end
        else
        begin
            if (
                state == STATE_WAIT_COMPLETE
                && batch_output_complete
            )
            begin
                state <=
                    STATE_IDLE;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (external_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            wrapper_protocol_error <=
                                1'b1;
                        end
                        else if (external_profile_command)
                        begin
                            state <=
                                STATE_PROFILE_Q;
                        end
                        else if (
                            external_batch_command
                            && profile_ready
                        )
                        begin
                            state <=
                                STATE_BATCH_HEADER;
                        end
                        else
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                STATE_DISCARD;
                        end
                    end
                end

                STATE_PROFILE_Q:
                begin
                    if (external_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:30] != 2'b00
                            || s_axis_tdata[63:62] != 2'b00
                            || !s_axis_tdata[29]
                            || !s_axis_tdata[61]
                        )
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            modulus_word <=
                                s_axis_tdata;

                            state <=
                                STATE_PROFILE_MU;
                        end
                    end
                end

                STATE_PROFILE_MU:
                begin
                    if (external_handshake)
                    begin
                        if (
                            !s_axis_tlast
                            || s_axis_tdata[31]
                            || s_axis_tdata[63]
                        )
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else
                        begin
                            mu_word <=
                                s_axis_tdata;

                            state <=
                                STATE_INJECT_EVAL_PROFILE_COMMAND;
                        end
                    end
                end

                STATE_INJECT_EVAL_PROFILE_COMMAND:
                begin
                    if (eval_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_EVAL_PROFILE_Q;
                    end
                end

                STATE_INJECT_EVAL_PROFILE_Q:
                begin
                    if (eval_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_EVAL_PROFILE_MU;
                    end
                end

                STATE_INJECT_EVAL_PROFILE_MU:
                begin
                    if (eval_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_BV_PROFILE_COMMAND;
                    end
                end

                STATE_INJECT_BV_PROFILE_COMMAND:
                begin
                    if (bv_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_BV_PROFILE_Q;
                    end
                end

                STATE_INJECT_BV_PROFILE_Q:
                begin
                    if (bv_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_BV_PROFILE_MU;
                    end
                end

                STATE_INJECT_BV_PROFILE_MU:
                begin
                    if (bv_input_handshake)
                    begin
                        profile_ready <=
                            1'b1;

                        completed_profiles <=
                            completed_profiles + 1'b1;

                        state <=
                            STATE_IDLE;
                    end
                end

                STATE_BATCH_HEADER:
                begin
                    if (external_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:0] == 32'd0
                            || s_axis_tdata[63:32] == 32'd0
                            || s_axis_tdata[63:32] > MAX_DIGITS
                        )
                        begin
                            wrapper_protocol_error <=
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

                            digit_count <=
                                s_axis_tdata[63:32];

                            active_batch_size <=
                                s_axis_tdata[31:0];

                            active_digit_count <=
                                s_axis_tdata[63:32];

                            input_ciphertext_index <=
                                32'd0;

                            input_coefficient_index <=
                                '0;

                            input_eval_section <=
                                1'b1;

                            input_eval_phase <=
                                2'd0;

                            input_bv_digit_index <=
                                '0;

                            input_bv_phase <=
                                2'd0;

                            state <=
                                STATE_INJECT_EVAL_BATCH_COMMAND;
                        end
                    end
                end

                STATE_INJECT_EVAL_BATCH_COMMAND:
                begin
                    if (eval_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_EVAL_BATCH_COUNT;
                    end
                end

                STATE_INJECT_EVAL_BATCH_COUNT:
                begin
                    if (eval_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_BV_BATCH_COMMAND;
                    end
                end

                STATE_INJECT_BV_BATCH_COMMAND:
                begin
                    if (bv_input_handshake)
                    begin
                        state <=
                            STATE_INJECT_BV_BATCH_HEADER;
                    end
                end

                STATE_INJECT_BV_BATCH_HEADER:
                begin
                    if (bv_input_handshake)
                    begin
                        state <=
                            STATE_PAYLOAD;
                    end
                end

                STATE_PAYLOAD:
                begin
                    if (external_handshake)
                    begin
                        if (
                            s_axis_tlast
                            != final_external_payload_word
                        )
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                s_axis_tlast
                                ? STATE_IDLE
                                : STATE_DISCARD;
                        end
                        else if (input_eval_section)
                        begin
                            if (input_eval_phase == 2'd3)
                            begin
                                input_eval_phase <=
                                    2'd0;

                                input_eval_section <=
                                    1'b0;

                                input_bv_digit_index <=
                                    '0;

                                input_bv_phase <=
                                    2'd0;
                            end
                            else
                            begin
                                input_eval_phase <=
                                    input_eval_phase + 1'b1;
                            end
                        end
                        else
                        begin
                            if (input_bv_phase == 2'd2)
                            begin
                                input_bv_phase <=
                                    2'd0;

                                if (final_bv_digit)
                                begin
                                    input_bv_digit_index <=
                                        '0;

                                    input_eval_section <=
                                        1'b1;

                                    input_eval_phase <=
                                        2'd0;

                                    if (final_coefficient)
                                    begin
                                        input_coefficient_index <=
                                            '0;

                                        if (final_ciphertext)
                                        begin
                                            state <=
                                                STATE_WAIT_COMPLETE;
                                        end
                                        else
                                        begin
                                            input_ciphertext_index <=
                                                input_ciphertext_index
                                                + 1'b1;
                                        end
                                    end
                                    else
                                    begin
                                        input_coefficient_index <=
                                            input_coefficient_index
                                            + 1'b1;
                                    end
                                end
                                else
                                begin
                                    input_bv_digit_index <=
                                        input_bv_digit_index
                                        + 1'b1;
                                end
                            end
                            else
                            begin
                                input_bv_phase <=
                                    input_bv_phase + 1'b1;
                            end
                        end
                    end
                end

                STATE_DISCARD:
                begin
                    if (
                        external_handshake
                        && s_axis_tlast
                    )
                    begin
                        state <=
                            STATE_IDLE;
                    end
                end

                default:
                begin
                end
            endcase
        end
    end

    /*
     * EvalMul3 alignment FIFO.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            eval_capture_component <=
                2'd0;

            eval_capture_c0 <=
                64'd0;

            eval_capture_c1 <=
                64'd0;

            eval_fifo_write_pointer <=
                '0;

            eval_fifo_read_pointer <=
                '0;

            eval_fifo_count <=
                '0;
        end
        else
        begin
            case ({
                eval_fifo_push,
                release_aligned_entry
            })
                2'b10:
                eval_fifo_count <=
                    eval_fifo_count + 1'b1;

                2'b01:
                eval_fifo_count <=
                    eval_fifo_count - 1'b1;

                default:
                begin
                end
            endcase

            if (eval_output_handshake)
            begin
                case (eval_capture_component)
                    2'd0:
                    begin
                        eval_capture_c0 <=
                            eval_m_axis_tdata;

                        eval_capture_component <=
                            2'd1;
                    end

                    2'd1:
                    begin
                        eval_capture_c1 <=
                            eval_m_axis_tdata;

                        eval_capture_component <=
                            2'd2;
                    end

                    default:
                    begin
                        eval_fifo_c0[
                            eval_fifo_write_pointer
                        ] <= eval_capture_c0;

                        eval_fifo_c1[
                            eval_fifo_write_pointer
                        ] <= eval_capture_c1;

                        eval_fifo_write_pointer <=
                            eval_fifo_write_pointer
                            + 1'b1;

                        eval_capture_component <=
                            2'd0;
                    end
                endcase
            end

            if (release_aligned_entry)
            begin
                eval_fifo_read_pointer <=
                    eval_fifo_read_pointer
                    + 1'b1;
            end
        end
    end

    /*
     * BV-MAC alignment FIFO.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            bv_capture_component <=
                1'b0;

            bv_capture_ks_b <=
                64'd0;

            bv_fifo_write_pointer <=
                '0;

            bv_fifo_read_pointer <=
                '0;

            bv_fifo_count <=
                '0;
        end
        else
        begin
            case ({
                bv_fifo_push,
                release_aligned_entry
            })
                2'b10:
                bv_fifo_count <=
                    bv_fifo_count + 1'b1;

                2'b01:
                bv_fifo_count <=
                    bv_fifo_count - 1'b1;

                default:
                begin
                end
            endcase

            if (bv_output_handshake)
            begin
                if (!bv_capture_component)
                begin
                    bv_capture_ks_b <=
                        bv_m_axis_tdata;

                    bv_capture_component <=
                        1'b1;
                end
                else
                begin
                    bv_fifo_ks_b[
                        bv_fifo_write_pointer
                    ] <= bv_capture_ks_b;

                    bv_fifo_ks_a[
                        bv_fifo_write_pointer
                    ] <= bv_m_axis_tdata;

                    bv_fifo_write_pointer <=
                        bv_fifo_write_pointer
                        + 1'b1;

                    bv_capture_component <=
                        1'b0;
                end
            end

            if (release_aligned_entry)
            begin
                bv_fifo_read_pointer <=
                    bv_fifo_read_pointer
                    + 1'b1;
            end
        end
    end

    /*
     * Final output framing and completion counters.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            output_component <=
                1'b0;

            output_ciphertext_index <=
                32'd0;

            output_coefficient_index <=
                '0;

            completed_ciphertexts <=
                32'd0;

            completed_batches <=
                32'd0;

            completed_coefficients <=
                32'd0;
        end
        else
        begin
            if (
                state == STATE_BATCH_HEADER
                && external_handshake
                && !s_axis_tlast
                && s_axis_tdata[31:0] != 32'd0
                && s_axis_tdata[63:32] != 32'd0
                && s_axis_tdata[63:32] <= MAX_DIGITS
            )
            begin
                output_component <=
                    1'b0;

                output_ciphertext_index <=
                    32'd0;

                output_coefficient_index <=
                    '0;
            end
            else if (output_handshake)
            begin
                if (!output_component)
                begin
                    output_component <=
                        1'b1;
                end
                else
                begin
                    output_component <=
                        1'b0;

                    completed_coefficients <=
                        completed_coefficients + 1'b1;

                    if (
                        output_coefficient_index
                        == LAST_COEFFICIENT
                    )
                    begin
                        output_coefficient_index <=
                            '0;

                        completed_ciphertexts <=
                            completed_ciphertexts + 1'b1;

                        if (final_output_word)
                        begin
                            completed_batches <=
                                completed_batches + 1'b1;
                        end
                        else
                        begin
                            output_ciphertext_index <=
                                output_ciphertext_index
                                + 1'b1;
                        end
                    end
                    else
                    begin
                        output_coefficient_index <=
                            output_coefficient_index
                            + 1'b1;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (reset_n)
        begin
            if (
                eval_fifo_push
                && eval_fifo_count == ALIGN_FIFO_DEPTH
                && !release_aligned_entry
            )
            begin
                $display(
                    "ERROR: EvalMul3 alignment FIFO overflow"
                );

                $fatal(1);
            end

            if (
                bv_fifo_push
                && bv_fifo_count == ALIGN_FIFO_DEPTH
                && !release_aligned_entry
            )
            begin
                $display(
                    "ERROR: BV alignment FIFO overflow"
                );

                $fatal(1);
            end

            if (
                release_aligned_entry
                && (
                    eval_fifo_count == 0
                    || bv_fifo_count == 0
                )
            )
            begin
                $display(
                    "ERROR: fused alignment FIFO underflow"
                );

                $fatal(1);
            end
        end
    end

    initial
    begin
        if (
            N < 2
            || (N & (N - 1)) != 0
        )
        begin
            $display(
                "ERROR: fused relinearization requires power-of-two N >= 2"
            );

            $fatal(1);
        end

        if (
            MAX_DIGITS < 1
            || (MAX_DIGITS & (MAX_DIGITS - 1)) != 0
        )
        begin
            $display(
                "ERROR: MAX_DIGITS must be a power of two"
            );

            $fatal(1);
        end

        if (
            ALIGN_FIFO_DEPTH < 4
            || (
                ALIGN_FIFO_DEPTH
                & (ALIGN_FIFO_DEPTH - 1)
            ) != 0
        )
        begin
            $display(
                "ERROR: ALIGN_FIFO_DEPTH must be power-of-two >= 4"
            );

            $fatal(1);
        end
    end

`endif

endmodule
