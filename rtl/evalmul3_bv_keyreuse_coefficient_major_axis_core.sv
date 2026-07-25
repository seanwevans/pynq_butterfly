`timescale 1ns/1ps

/*
 * Coefficient-major exact two-tower EvalMul plus host-decomposed OpenFHE BV
 * relinearization with evaluation-key reuse across a ciphertext batch.
 *
 * Profile frame:
 *
 *     word 0: { "RLPF", "RLPF" }
 *     word 1: { q1, q0 }
 *     word 2: { mu1, mu0 }, TLAST
 *
 * Batch frame:
 *
 *     word 0: { "RLCM", "RLCM" }
 *     word 1: { digit_count, ciphertext_count }
 *
 * For each ring coefficient:
 *
 *     for each ciphertext:
 *         a0
 *         a1
 *         b0
 *         b1
 *
 *     for each BV digit:
 *         eval_key_b
 *         eval_key_a
 *
 *         for each ciphertext:
 *             digit
 *
 * Output order:
 *
 *     for each ring coefficient:
 *         for each ciphertext:
 *             relin_c0
 *             relin_c1
 *
 * Evaluation-key words are supplied once per coefficient and digit, then held
 * while the batch's digit words stream through four Barrett multipliers.
 *
 * The first checkpoint serializes output of one completed coefficient before
 * accepting the next coefficient. This keeps the functional architecture
 * simple while still reducing input traffic from 40B words/coefficient to
 * 16B+24 words/coefficient for 12 BV digits.
 *
 * Because BV decomposition digits are supplied by the host, this core does
 * not calculate c2=a1*b1. It needs six EvalMul Barrett pipelines for c0/c1
 * plus four BV-MAC pipelines: ten pipelines total, or 160 DSP48E1.
 */
module evalmul3_bv_keyreuse_coefficient_major_axis_core #(
    parameter integer N = 4096,
    parameter integer MAX_BATCH = 64,
    parameter integer MIN_BATCH = 8,
    parameter integer MAX_DIGITS = 16,
    parameter integer EVAL_META_DEPTH = 16,
    parameter integer BV_META_DEPTH = 32
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
        (N <= 2)
        ? 1
        : $clog2(N);

    localparam integer BATCH_WIDTH =
        (MAX_BATCH <= 2)
        ? 1
        : $clog2(MAX_BATCH);

    localparam integer DIGIT_WIDTH =
        (MAX_DIGITS <= 1)
        ? 1
        : $clog2(MAX_DIGITS);

    localparam integer EVAL_META_PTR_WIDTH =
        (EVAL_META_DEPTH <= 2)
        ? 1
        : $clog2(EVAL_META_DEPTH);

    localparam integer BV_META_PTR_WIDTH =
        (BV_META_DEPTH <= 2)
        ? 1
        : $clog2(BV_META_DEPTH);

    localparam logic [INDEX_WIDTH-1:0] LAST_COEFFICIENT =
        N - 1;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h524c5046;  // "RLPF"

    localparam logic [31:0] COMMAND_BATCH =
        32'h524c434d;  // "RLCM"

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PROFILE_Q,
        STATE_PROFILE_MU,
        STATE_BATCH_HEADER,
        STATE_COEFFICIENT_EVAL,
        STATE_COEFFICIENT_KEY_B,
        STATE_COEFFICIENT_KEY_A,
        STATE_COEFFICIENT_DIGITS,
        STATE_WAIT_COMPUTE,
        STATE_OUTPUT,
        STATE_DISCARD
    } state_t;

    state_t state;

    logic wrapper_protocol_error;

    logic [63:0] modulus_word;
    logic [63:0] mu_word;

    logic [31:0] batch_count;
    logic [31:0] digit_count;

    logic [INDEX_WIDTH-1:0] coefficient_index;

    logic [BATCH_WIDTH-1:0] eval_input_ciphertext;
    logic [1:0]             eval_input_phase;

    logic [DIGIT_WIDTH-1:0] bv_input_digit;
    logic [BATCH_WIDTH-1:0] bv_input_ciphertext;

    logic [63:0] eval_a0_word;
    logic [63:0] eval_a1_word;
    logic [63:0] eval_b0_word;

    logic [63:0] bv_key_b_word;
    logic [63:0] bv_key_a_word;

    logic [BATCH_WIDTH-1:0] output_ciphertext;
    logic                   output_component;

    logic [31:0] eval_result_count;
    logic [31:0] bv_final_result_count;

    logic [63:0] c0_memory   [0:MAX_BATCH-1];
    logic [63:0] c1_memory   [0:MAX_BATCH-1];
    logic [63:0] ks_b_memory [0:MAX_BATCH-1];
    logic [63:0] ks_a_memory [0:MAX_BATCH-1];

    function automatic [31:0] add_mod32;
        input [31:0] x;
        input [31:0] y;
        input [31:0] q;

        reg [32:0] sum_value;
    begin
        sum_value =
            {
                1'b0,
                x
            } + {
                1'b0,
                y
            };

        if (
            sum_value
            >= {
                1'b0,
                q
            }
        )
        begin
            add_mod32 =
                sum_value[31:0]
                - q;
        end
        else
        begin
            add_mod32 =
                sum_value[31:0];
        end
    end
    endfunction

    function automatic [63:0] add_mod_pair;
        input [63:0] x;
        input [63:0] y;
        input [63:0] q;
    begin
        add_mod_pair = {
            add_mod32(
                x[63:32],
                y[63:32],
                q[63:32]
            ),
            add_mod32(
                x[31:0],
                y[31:0],
                q[31:0]
            )
        };
    end
    endfunction

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

    wire final_input_ciphertext =
        eval_input_ciphertext + 1'b1
        == batch_count;

    wire final_bv_ciphertext =
        bv_input_ciphertext + 1'b1
        == batch_count;

    wire final_bv_digit =
        bv_input_digit + 1'b1
        == digit_count;

    wire final_external_payload_word =
        state == STATE_COEFFICIENT_DIGITS
        && final_bv_ciphertext
        && final_bv_digit
        && coefficient_index == LAST_COEFFICIENT;

    wire accepted_batch_header =
        state == STATE_BATCH_HEADER
        && external_handshake
        && !s_axis_tlast
        && s_axis_tdata[31:0] >= MIN_BATCH
        && s_axis_tdata[31:0] <= MAX_BATCH
        && s_axis_tdata[63:32] != 32'd0
        && s_axis_tdata[63:32] <= MAX_DIGITS;

    wire output_handshake =
        m_axis_tvalid
        && m_axis_tready;

    wire output_coefficient_complete =
        state == STATE_OUTPUT
        && output_handshake
        && output_component
        && output_ciphertext + 1'b1
            == batch_count;

    wire output_batch_complete =
        output_coefficient_complete
        && coefficient_index
            == LAST_COEFFICIENT;

    wire start_coefficient_event =
        accepted_batch_header
        || (
            output_coefficient_complete
            && coefficient_index
                != LAST_COEFFICIENT
        );

    /*
     * EvalMul launch: one ciphertext every four accepted input words.
     */
    wire eval_launch =
        state == STATE_COEFFICIENT_EVAL
        && external_handshake
        && eval_input_phase == 2'd3;

    wire [31:0] eval_a0_lane0 =
        eval_a0_word[31:0];

    wire [31:0] eval_a0_lane1 =
        eval_a0_word[63:32];

    wire [31:0] eval_a1_lane0 =
        eval_a1_word[31:0];

    wire [31:0] eval_a1_lane1 =
        eval_a1_word[63:32];

    wire [31:0] eval_b0_lane0 =
        eval_b0_word[31:0];

    wire [31:0] eval_b0_lane1 =
        eval_b0_word[63:32];

    wire [31:0] eval_b1_lane0 =
        s_axis_tdata[31:0];

    wire [31:0] eval_b1_lane1 =
        s_axis_tdata[63:32];

    wire eval_c0_valid_lane0;
    wire eval_x1_valid_lane0;
    wire eval_x2_valid_lane0;

    wire eval_c0_valid_lane1;
    wire eval_x1_valid_lane1;
    wire eval_x2_valid_lane1;

    wire [31:0] eval_c0_result_lane0;
    wire [31:0] eval_x1_result_lane0;
    wire [31:0] eval_x2_result_lane0;

    wire [31:0] eval_c0_result_lane1;
    wire [31:0] eval_x1_result_lane1;
    wire [31:0] eval_x2_result_lane1;

    modmul_barrett60_pipeline_split_core eval_c0_lane0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (eval_launch),
        .a            (eval_a0_lane0),
        .b            (eval_b0_lane0),
        .q            (modulus_word[31:0]),
        .mu           (mu_word[30:0]),
        .output_valid (eval_c0_valid_lane0),
        .result       (eval_c0_result_lane0)
    );

    modmul_barrett60_pipeline_split_core eval_x1_lane0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (eval_launch),
        .a            (eval_a0_lane0),
        .b            (eval_b1_lane0),
        .q            (modulus_word[31:0]),
        .mu           (mu_word[30:0]),
        .output_valid (eval_x1_valid_lane0),
        .result       (eval_x1_result_lane0)
    );

    modmul_barrett60_pipeline_split_core eval_x2_lane0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (eval_launch),
        .a            (eval_a1_lane0),
        .b            (eval_b0_lane0),
        .q            (modulus_word[31:0]),
        .mu           (mu_word[30:0]),
        .output_valid (eval_x2_valid_lane0),
        .result       (eval_x2_result_lane0)
    );

    modmul_barrett60_pipeline_split_core eval_c0_lane1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (eval_launch),
        .a            (eval_a0_lane1),
        .b            (eval_b0_lane1),
        .q            (modulus_word[63:32]),
        .mu           (mu_word[62:32]),
        .output_valid (eval_c0_valid_lane1),
        .result       (eval_c0_result_lane1)
    );

    modmul_barrett60_pipeline_split_core eval_x1_lane1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (eval_launch),
        .a            (eval_a0_lane1),
        .b            (eval_b1_lane1),
        .q            (modulus_word[63:32]),
        .mu           (mu_word[62:32]),
        .output_valid (eval_x1_valid_lane1),
        .result       (eval_x1_result_lane1)
    );

    modmul_barrett60_pipeline_split_core eval_x2_lane1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (eval_launch),
        .a            (eval_a1_lane1),
        .b            (eval_b0_lane1),
        .q            (modulus_word[63:32]),
        .mu           (mu_word[62:32]),
        .output_valid (eval_x2_valid_lane1),
        .result       (eval_x2_result_lane1)
    );

    wire eval_result_valid =
        eval_c0_valid_lane0;

    wire [63:0] eval_result_c0 = {
        eval_c0_result_lane1,
        eval_c0_result_lane0
    };

    wire [63:0] eval_result_c1 = {
        add_mod32(
            eval_x1_result_lane1,
            eval_x2_result_lane1,
            modulus_word[63:32]
        ),
        add_mod32(
            eval_x1_result_lane0,
            eval_x2_result_lane0,
            modulus_word[31:0]
        )
    };

    /*
     * Eval launch metadata FIFO.
     */
    logic [BATCH_WIDTH-1:0] eval_meta_ciphertext [0:EVAL_META_DEPTH-1];

    logic [EVAL_META_PTR_WIDTH-1:0] eval_meta_write_pointer;
    logic [EVAL_META_PTR_WIDTH-1:0] eval_meta_read_pointer;
    logic [EVAL_META_PTR_WIDTH:0]   eval_meta_count;

    wire eval_meta_has_credit =
        eval_meta_count < EVAL_META_DEPTH;

    wire eval_meta_push =
        eval_launch;

    wire eval_meta_pop =
        eval_result_valid;

    /*
     * BV key-reuse launch.
     */
    wire bv_launch =
        state == STATE_COEFFICIENT_DIGITS
        && external_handshake;

    wire [31:0] bv_digit_lane0 =
        s_axis_tdata[31:0];

    wire [31:0] bv_digit_lane1 =
        s_axis_tdata[63:32];

    wire bv_b_valid_lane0;
    wire bv_a_valid_lane0;
    wire bv_b_valid_lane1;
    wire bv_a_valid_lane1;

    wire [31:0] bv_b_result_lane0;
    wire [31:0] bv_a_result_lane0;
    wire [31:0] bv_b_result_lane1;
    wire [31:0] bv_a_result_lane1;

    modmul_barrett60_pipeline_split_core bv_b_lane0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (bv_launch),
        .a            (bv_digit_lane0),
        .b            (bv_key_b_word[31:0]),
        .q            (modulus_word[31:0]),
        .mu           (mu_word[30:0]),
        .output_valid (bv_b_valid_lane0),
        .result       (bv_b_result_lane0)
    );

    modmul_barrett60_pipeline_split_core bv_a_lane0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (bv_launch),
        .a            (bv_digit_lane0),
        .b            (bv_key_a_word[31:0]),
        .q            (modulus_word[31:0]),
        .mu           (mu_word[30:0]),
        .output_valid (bv_a_valid_lane0),
        .result       (bv_a_result_lane0)
    );

    modmul_barrett60_pipeline_split_core bv_b_lane1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (bv_launch),
        .a            (bv_digit_lane1),
        .b            (bv_key_b_word[63:32]),
        .q            (modulus_word[63:32]),
        .mu           (mu_word[62:32]),
        .output_valid (bv_b_valid_lane1),
        .result       (bv_b_result_lane1)
    );

    modmul_barrett60_pipeline_split_core bv_a_lane1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .input_valid  (bv_launch),
        .a            (bv_digit_lane1),
        .b            (bv_key_a_word[63:32]),
        .q            (modulus_word[63:32]),
        .mu           (mu_word[62:32]),
        .output_valid (bv_a_valid_lane1),
        .result       (bv_a_result_lane1)
    );

    wire bv_result_valid =
        bv_b_valid_lane0;

    wire [63:0] bv_result_b = {
        bv_b_result_lane1,
        bv_b_result_lane0
    };

    wire [63:0] bv_result_a = {
        bv_a_result_lane1,
        bv_a_result_lane0
    };

    /*
     * BV launch metadata FIFO.
     */
    logic [BATCH_WIDTH-1:0] bv_meta_ciphertext [0:BV_META_DEPTH-1];
    logic [DIGIT_WIDTH-1:0] bv_meta_digit      [0:BV_META_DEPTH-1];

    logic [BV_META_PTR_WIDTH-1:0] bv_meta_write_pointer;
    logic [BV_META_PTR_WIDTH-1:0] bv_meta_read_pointer;
    logic [BV_META_PTR_WIDTH:0]   bv_meta_count;

    wire bv_meta_has_credit =
        bv_meta_count < BV_META_DEPTH;

    wire bv_meta_push =
        bv_launch;

    wire bv_meta_pop =
        bv_result_valid;

    /*
     * External input readiness. The metadata FIFOs absorb the fixed-latency
     * multiplier pipelines.
     */
    always @*
    begin
        case (state)
            STATE_IDLE,
            STATE_PROFILE_Q,
            STATE_PROFILE_MU,
            STATE_BATCH_HEADER,
            STATE_COEFFICIENT_KEY_B,
            STATE_COEFFICIENT_KEY_A,
            STATE_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            STATE_COEFFICIENT_EVAL:
            begin
                if (eval_input_phase == 2'd3)
                begin
                    s_axis_tready =
                        eval_meta_has_credit;
                end
                else
                begin
                    s_axis_tready =
                        1'b1;
                end
            end

            STATE_COEFFICIENT_DIGITS:
            begin
                s_axis_tready =
                    bv_meta_has_credit;
            end

            default:
            begin
                s_axis_tready =
                    1'b0;
            end
        endcase
    end

    /*
     * Final modular additions and AXI output.
     */
    wire [63:0] output_c0 =
        c0_memory[
            output_ciphertext
        ];

    wire [63:0] output_c1 =
        c1_memory[
            output_ciphertext
        ];

    wire [63:0] output_ks_b =
        ks_b_memory[
            output_ciphertext
        ];

    wire [63:0] output_ks_a =
        ks_a_memory[
            output_ciphertext
        ];

    assign m_axis_tvalid =
        state == STATE_OUTPUT;

    assign m_axis_tdata =
        state != STATE_OUTPUT
        ? 64'd0
        : output_component
        ? add_mod_pair(
            output_c1,
            output_ks_a,
            modulus_word
        )
        : add_mod_pair(
            output_c0,
            output_ks_b,
            modulus_word
        );

    assign m_axis_tlast =
        state == STATE_OUTPUT
        && output_component
        && output_ciphertext + 1'b1
            == batch_count
        && coefficient_index
            == LAST_COEFFICIENT;

    assign protocol_error =
        wrapper_protocol_error;

    assign accelerator_busy =
        state != STATE_IDLE
        || eval_meta_count != 0
        || bv_meta_count != 0;

    /*
     * External protocol and coefficient scheduler.
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

            coefficient_index <=
                '0;

            eval_input_ciphertext <=
                '0;

            eval_input_phase <=
                2'd0;

            eval_a0_word <=
                64'd0;

            eval_a1_word <=
                64'd0;

            eval_b0_word <=
                64'd0;

            bv_input_digit <=
                '0;

            bv_input_ciphertext <=
                '0;

            bv_key_b_word <=
                64'd0;

            bv_key_a_word <=
                64'd0;

            output_ciphertext <=
                '0;

            output_component <=
                1'b0;

            profile_ready <=
                1'b0;

            completed_profiles <=
                32'd0;

            completed_ciphertexts <=
                32'd0;

            completed_batches <=
                32'd0;

            completed_coefficients <=
                32'd0;
        end
        else
        begin
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
                            || s_axis_tdata[31:30]
                                != 2'b00
                            || s_axis_tdata[63:62]
                                != 2'b00
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

                            profile_ready <=
                                1'b1;

                            completed_profiles <=
                                completed_profiles
                                + 1'b1;

                            state <=
                                STATE_IDLE;
                        end
                    end
                end

                STATE_BATCH_HEADER:
                begin
                    if (external_handshake)
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

                            coefficient_index <=
                                '0;

                            eval_input_ciphertext <=
                                '0;

                            eval_input_phase <=
                                2'd0;

                            bv_input_digit <=
                                '0;

                            bv_input_ciphertext <=
                                '0;

                            output_ciphertext <=
                                '0;

                            output_component <=
                                1'b0;

                            state <=
                                STATE_COEFFICIENT_EVAL;
                        end
                    end
                end

                STATE_COEFFICIENT_EVAL:
                begin
                    if (external_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            case (eval_input_phase)
                                2'd0:
                                begin
                                    eval_a0_word <=
                                        s_axis_tdata;

                                    eval_input_phase <=
                                        2'd1;
                                end

                                2'd1:
                                begin
                                    eval_a1_word <=
                                        s_axis_tdata;

                                    eval_input_phase <=
                                        2'd2;
                                end

                                2'd2:
                                begin
                                    eval_b0_word <=
                                        s_axis_tdata;

                                    eval_input_phase <=
                                        2'd3;
                                end

                                default:
                                begin
                                    eval_input_phase <=
                                        2'd0;

                                    if (
                                        final_input_ciphertext
                                    )
                                    begin
                                        eval_input_ciphertext <=
                                            '0;

                                        state <=
                                            STATE_COEFFICIENT_KEY_B;
                                    end
                                    else
                                    begin
                                        eval_input_ciphertext <=
                                            eval_input_ciphertext
                                            + 1'b1;
                                    end
                                end
                            endcase
                        end
                    end
                end

                STATE_COEFFICIENT_KEY_B:
                begin
                    if (external_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            bv_key_b_word <=
                                s_axis_tdata;

                            state <=
                                STATE_COEFFICIENT_KEY_A;
                        end
                    end
                end

                STATE_COEFFICIENT_KEY_A:
                begin
                    if (external_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            wrapper_protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            bv_key_a_word <=
                                s_axis_tdata;

                            bv_input_ciphertext <=
                                '0;

                            state <=
                                STATE_COEFFICIENT_DIGITS;
                        end
                    end
                end

                STATE_COEFFICIENT_DIGITS:
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
                        else if (
                            final_bv_ciphertext
                        )
                        begin
                            bv_input_ciphertext <=
                                '0;

                            if (final_bv_digit)
                            begin
                                bv_input_digit <=
                                    '0;

                                state <=
                                    STATE_WAIT_COMPUTE;
                            end
                            else
                            begin
                                bv_input_digit <=
                                    bv_input_digit
                                    + 1'b1;

                                state <=
                                    STATE_COEFFICIENT_KEY_B;
                            end
                        end
                        else
                        begin
                            bv_input_ciphertext <=
                                bv_input_ciphertext
                                + 1'b1;
                        end
                    end
                end

                STATE_WAIT_COMPUTE:
                begin
                    if (
                        eval_result_count
                            == batch_count
                        && bv_final_result_count
                            == batch_count
                    )
                    begin
                        output_ciphertext <=
                            '0;

                        output_component <=
                            1'b0;

                        state <=
                            STATE_OUTPUT;
                    end
                end

                STATE_OUTPUT:
                begin
                    if (output_handshake)
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
                                completed_coefficients
                                + 1'b1;

                            if (
                                output_ciphertext
                                + 1'b1
                                == batch_count
                            )
                            begin
                                output_ciphertext <=
                                    '0;

                                if (
                                    coefficient_index
                                    == LAST_COEFFICIENT
                                )
                                begin
                                    completed_ciphertexts <=
                                        completed_ciphertexts
                                        + batch_count;

                                    completed_batches <=
                                        completed_batches
                                        + 1'b1;

                                    state <=
                                        STATE_IDLE;
                                end
                                else
                                begin
                                    coefficient_index <=
                                        coefficient_index
                                        + 1'b1;

                                    eval_input_ciphertext <=
                                        '0;

                                    eval_input_phase <=
                                        2'd0;

                                    bv_input_digit <=
                                        '0;

                                    bv_input_ciphertext <=
                                        '0;

                                    state <=
                                        STATE_COEFFICIENT_EVAL;
                                end
                            end
                            else
                            begin
                                output_ciphertext <=
                                    output_ciphertext
                                    + 1'b1;
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
                    state <=
                        STATE_IDLE;
                end
            endcase
        end
    end

    /*
     * Eval metadata FIFO and result storage.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            eval_meta_write_pointer <=
                '0;

            eval_meta_read_pointer <=
                '0;

            eval_meta_count <=
                '0;

            eval_result_count <=
                32'd0;
        end
        else
        begin
            if (start_coefficient_event)
            begin
                eval_result_count <=
                    32'd0;
            end
            else if (eval_meta_pop)
            begin
                eval_result_count <=
                    eval_result_count
                    + 1'b1;
            end

            case ({
                eval_meta_push,
                eval_meta_pop
            })
                2'b10:
                eval_meta_count <=
                    eval_meta_count
                    + 1'b1;

                2'b01:
                eval_meta_count <=
                    eval_meta_count
                    - 1'b1;

                default:
                begin
                end
            endcase

            if (eval_meta_push)
            begin
                eval_meta_ciphertext[
                    eval_meta_write_pointer
                ] <= eval_input_ciphertext;

                eval_meta_write_pointer <=
                    eval_meta_write_pointer
                    + 1'b1;
            end

            if (eval_meta_pop)
            begin
                c0_memory[
                    eval_meta_ciphertext[
                        eval_meta_read_pointer
                    ]
                ] <= eval_result_c0;

                c1_memory[
                    eval_meta_ciphertext[
                        eval_meta_read_pointer
                    ]
                ] <= eval_result_c1;

                eval_meta_read_pointer <=
                    eval_meta_read_pointer
                    + 1'b1;
            end
        end
    end

    /*
     * BV metadata FIFO and per-ciphertext accumulators.
     *
     * MIN_BATCH=8 guarantees that the same accumulator address is not revisited
     * until the prior seven-cycle multiplier result has been committed.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            bv_meta_write_pointer <=
                '0;

            bv_meta_read_pointer <=
                '0;

            bv_meta_count <=
                '0;

            bv_final_result_count <=
                32'd0;
        end
        else
        begin
            if (start_coefficient_event)
            begin
                bv_final_result_count <=
                    32'd0;
            end
            else if (
                bv_meta_pop
                && bv_meta_digit[
                    bv_meta_read_pointer
                ] + 1'b1
                    == digit_count
            )
            begin
                bv_final_result_count <=
                    bv_final_result_count
                    + 1'b1;
            end

            case ({
                bv_meta_push,
                bv_meta_pop
            })
                2'b10:
                bv_meta_count <=
                    bv_meta_count
                    + 1'b1;

                2'b01:
                bv_meta_count <=
                    bv_meta_count
                    - 1'b1;

                default:
                begin
                end
            endcase

            if (bv_meta_push)
            begin
                bv_meta_ciphertext[
                    bv_meta_write_pointer
                ] <= bv_input_ciphertext;

                bv_meta_digit[
                    bv_meta_write_pointer
                ] <= bv_input_digit;

                bv_meta_write_pointer <=
                    bv_meta_write_pointer
                    + 1'b1;
            end

            if (bv_meta_pop)
            begin
                if (
                    bv_meta_digit[
                        bv_meta_read_pointer
                    ] == 0
                )
                begin
                    ks_b_memory[
                        bv_meta_ciphertext[
                            bv_meta_read_pointer
                        ]
                    ] <= bv_result_b;

                    ks_a_memory[
                        bv_meta_ciphertext[
                            bv_meta_read_pointer
                        ]
                    ] <= bv_result_a;
                end
                else
                begin
                    ks_b_memory[
                        bv_meta_ciphertext[
                            bv_meta_read_pointer
                        ]
                    ] <= add_mod_pair(
                        ks_b_memory[
                            bv_meta_ciphertext[
                                bv_meta_read_pointer
                            ]
                        ],
                        bv_result_b,
                        modulus_word
                    );

                    ks_a_memory[
                        bv_meta_ciphertext[
                            bv_meta_read_pointer
                        ]
                    ] <= add_mod_pair(
                        ks_a_memory[
                            bv_meta_ciphertext[
                                bv_meta_read_pointer
                            ]
                        ],
                        bv_result_a,
                        modulus_word
                    );
                end

                bv_meta_read_pointer <=
                    bv_meta_read_pointer
                    + 1'b1;
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (reset_n)
        begin
            if (
                eval_meta_push
                && eval_meta_count
                    == EVAL_META_DEPTH
                && !eval_meta_pop
            )
            begin
                $display(
                    "ERROR: Eval metadata FIFO overflow"
                );

                $fatal(1);
            end

            if (
                eval_meta_pop
                && eval_meta_count == 0
            )
            begin
                $display(
                    "ERROR: Eval metadata FIFO underflow"
                );

                $fatal(1);
            end

            if (
                bv_meta_push
                && bv_meta_count
                    == BV_META_DEPTH
                && !bv_meta_pop
            )
            begin
                $display(
                    "ERROR: BV metadata FIFO overflow"
                );

                $fatal(1);
            end

            if (
                bv_meta_pop
                && bv_meta_count == 0
            )
            begin
                $display(
                    "ERROR: BV metadata FIFO underflow"
                );

                $fatal(1);
            end

            if (
                eval_result_valid
                && !(
                    eval_c0_valid_lane0
                    && eval_x1_valid_lane0
                    && eval_x2_valid_lane0
                    && eval_c0_valid_lane1
                    && eval_x1_valid_lane1
                    && eval_x2_valid_lane1
                )
            )
            begin
                $display(
                    "ERROR: Eval multiplier valid signals diverged"
                );

                $fatal(1);
            end

            if (
                bv_result_valid
                && !(
                    bv_b_valid_lane0
                    && bv_a_valid_lane0
                    && bv_b_valid_lane1
                    && bv_a_valid_lane1
                )
            )
            begin
                $display(
                    "ERROR: BV multiplier valid signals diverged"
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
                "ERROR: N must be a power of two >= 2"
            );

            $fatal(1);
        end

        if (
            MIN_BATCH < 8
            || MIN_BATCH > MAX_BATCH
        )
        begin
            $display(
                "ERROR: require 8 <= MIN_BATCH <= MAX_BATCH"
            );

            $fatal(1);
        end

        if (
            MAX_BATCH < 8
            || (MAX_BATCH & (MAX_BATCH - 1))
                != 0
        )
        begin
            $display(
                "ERROR: MAX_BATCH must be a power of two >= 8"
            );

            $fatal(1);
        end

        if (
            MAX_DIGITS < 1
            || (MAX_DIGITS & (MAX_DIGITS - 1))
                != 0
        )
        begin
            $display(
                "ERROR: MAX_DIGITS must be a power of two"
            );

            $fatal(1);
        end

        if (
            EVAL_META_DEPTH < 8
            || (
                EVAL_META_DEPTH
                & (EVAL_META_DEPTH - 1)
            ) != 0
        )
        begin
            $display(
                "ERROR: EVAL_META_DEPTH must be power-of-two >= 8"
            );

            $fatal(1);
        end

        if (
            BV_META_DEPTH < 16
            || (
                BV_META_DEPTH
                & (BV_META_DEPTH - 1)
            ) != 0
        )
        begin
            $display(
                "ERROR: BV_META_DEPTH must be power-of-two >= 16"
            );

            $fatal(1);
        end
    end

`endif

endmodule
