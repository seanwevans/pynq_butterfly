`timescale 1ns/1ps

/*
 * Two-tower OpenFHE BV key-switch multiply-accumulate core.
 *
 * This is the first relinearization datapath checkpoint. It consumes exact
 * OpenFHE BV decomposition digits and evaluation-key A/B polynomials, all in
 * Format::EVALUATION, and computes:
 *
 *     ks_b = sum_j digit_j * eval_key_b_j mod q
 *     ks_a = sum_j digit_j * eval_key_a_j mod q
 *
 * for two packed RNS towers:
 *
 *     bits 31:0  = tower lane 0
 *     bits 63:32 = tower lane 1
 *
 * Profile frame:
 *
 *     word 0: { "BVPF", "BVPF" }
 *     word 1: { q1, q0 }
 *     word 2: { mu1, mu0 }, TLAST=1
 *
 * where mu = floor(2^60/q), carried in 31 bits.
 *
 * Batch frame:
 *
 *     word 0: { "BVKM", "BVKM" }
 *     word 1: { digit_count, ciphertext_count }
 *
 *     for each ciphertext, coefficient, and decomposition digit:
 *
 *         digit_j
 *         eval_key_b_j
 *         eval_key_a_j
 *
 * The final eval_key_a word carries TLAST.
 *
 * Output order for every coefficient:
 *
 *     ks_b
 *     ks_a
 *
 * The final ks_a word carries TLAST.
 *
 * Four Barrett pipelines are used:
 *
 *     two key components x two packed towers
 *
 * One digit launches every three input clocks, so the 64-bit input stream is
 * the steady-state limit. A result FIFO permits arbitrary output backpressure.
 */
module bv_keyswitch_mac_two_tower_axis_core #(
    parameter integer N = 4096,
    parameter integer MAX_DIGITS = 16,
    parameter integer FIFO_DEPTH = 8
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
    output logic [31:0] launched_digit_products,
    output logic [31:0] completed_coefficients
);

    localparam integer INDEX_WIDTH =
        (N <= 2) ? 1 : $clog2(N);

    /*
     * One extra representable value is required for the runtime
     * index-plus-one comparisons when digit_count == MAX_DIGITS.
     */
    localparam integer DIGIT_WIDTH =
        (MAX_DIGITS <= 1) ? 1 : $clog2(MAX_DIGITS + 1);

    localparam integer FIFO_PTR_WIDTH =
        (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);

    localparam logic [INDEX_WIDTH-1:0] LAST_COEFFICIENT =
        N - 1;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h42565046;  // "BVPF"

    localparam logic [31:0] COMMAND_MAC =
        32'h42564b4d;  // "BVKM"

    typedef enum logic [2:0] {
        INPUT_IDLE,
        INPUT_PROFILE_Q,
        INPUT_PROFILE_MU,
        INPUT_BATCH_HEADER,
        INPUT_DATA,
        INPUT_WAIT_COMPLETE,
        INPUT_DISCARD
    } input_state_t;

    input_state_t input_state;

    logic [63:0] modulus_register;
    logic [61:0] mu_register;

    assign active_modulus =
        modulus_register;

    assign active_modulus_mu =
        mu_register;

    logic [31:0] batch_count;
    logic [31:0] digit_count;

    logic [31:0] input_ciphertext_index;
    logic [INDEX_WIDTH-1:0] input_coefficient_index;
    logic [DIGIT_WIDTH-1:0] input_digit_index;
    logic [1:0] input_operand_phase;

    logic [63:0] operand_digit;
    logic [63:0] operand_key_b;

    wire input_handshake =
        s_axis_tvalid
        && s_axis_tready;

    wire output_handshake =
        m_axis_tvalid
        && m_axis_tready;

    wire profile_command =
        s_axis_tdata == {
            COMMAND_PROFILE,
            COMMAND_PROFILE
        };

    wire mac_command =
        s_axis_tdata == {
            COMMAND_MAC,
            COMMAND_MAC
        };

    wire batch_header_accepted =
        input_handshake
        && input_state == INPUT_BATCH_HEADER
        && !s_axis_tlast
        && s_axis_tdata[31:0] != 32'd0
        && s_axis_tdata[63:32] != 32'd0
        && s_axis_tdata[63:32] <= MAX_DIGITS;

    wire final_digit_input =
        input_state == INPUT_DATA
        && input_operand_phase == 2'd2
        && input_digit_index + 1'b1 == digit_count;

    wire final_input_word =
        final_digit_input
        && input_coefficient_index == LAST_COEFFICIENT
        && input_ciphertext_index + 1'b1 == batch_count;

    wire coefficient_input_start =
        input_state == INPUT_DATA
        && input_operand_phase == 2'd0
        && input_digit_index == 0;

    wire reserve_result_slot =
        input_handshake
        && coefficient_input_start;

    wire launch_valid =
        input_handshake
        && input_state == INPUT_DATA
        && input_operand_phase == 2'd2;

    /*
     * Reserve one coefficient result slot before accepting its first digit.
     * The reservation remains occupied through all digit products and until
     * both output words have been accepted.
     */
    logic [FIFO_PTR_WIDTH:0] reserved_count;
    logic [FIFO_PTR_WIDTH:0] fifo_count;

    wire fifo_has_credit =
        reserved_count < FIFO_DEPTH;

    always @*
    begin
        s_axis_tready =
            1'b0;

        case (input_state)
            INPUT_IDLE,
            INPUT_PROFILE_Q,
            INPUT_PROFILE_MU,
            INPUT_BATCH_HEADER,
            INPUT_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            INPUT_DATA:
            begin
                s_axis_tready =
                    !coefficient_input_start
                    || fifo_has_credit;
            end

            default:
            begin
            end
        endcase
    end

    /*
     * Two towers and two evaluation-key components.
     */
    logic [1:0][1:0][31:0] multiplier_a;
    logic [1:0][1:0][31:0] multiplier_b;
    logic [1:0][1:0][31:0] multiplier_result;
    logic [1:0][1:0]       multiplier_output_valid;

    logic [1:0][31:0] modulus_lane;
    logic [1:0][30:0] mu_lane;

    assign modulus_lane[0] =
        modulus_register[31:0];

    assign modulus_lane[1] =
        modulus_register[63:32];

    assign mu_lane[0] =
        mu_register[30:0];

    assign mu_lane[1] =
        mu_register[61:31];

    /*
     * Keep packed-array lane selection constant. Vivado accepts the compact
     * loop form, but Icarus requires constant indices for these nested packed
     * dimensions during elaboration.
     */
    always @*
    begin
        multiplier_a =
            '0;

        multiplier_b =
            '0;

        multiplier_a[0][0] =
            operand_digit[31:0];

        multiplier_b[0][0] =
            operand_key_b[31:0];

        multiplier_a[0][1] =
            operand_digit[31:0];

        multiplier_b[0][1] =
            s_axis_tdata[31:0];

        multiplier_a[1][0] =
            operand_digit[63:32];

        multiplier_b[1][0] =
            operand_key_b[63:32];

        multiplier_a[1][1] =
            operand_digit[63:32];

        multiplier_b[1][1] =
            s_axis_tdata[63:32];
    end

    generate
        genvar tower_index;
        genvar component_index;

        for (
            tower_index = 0;
            tower_index < 2;
            tower_index = tower_index + 1
        )
        begin : multiplier_towers
            for (
                component_index = 0;
                component_index < 2;
                component_index = component_index + 1
            )
            begin : multiplier_components
                modmul_barrett60_pipeline_split_core multiplier (
                    .clk          (clk),
                    .reset_n      (reset_n),
                    .input_valid  (launch_valid),
                    .a            (
                        multiplier_a[
                            tower_index
                        ][
                            component_index
                        ]
                    ),
                    .b            (
                        multiplier_b[
                            tower_index
                        ][
                            component_index
                        ]
                    ),
                    .q            (
                        modulus_lane[
                            tower_index
                        ]
                    ),
                    .mu           (
                        mu_lane[
                            tower_index
                        ]
                    ),
                    .output_valid (
                        multiplier_output_valid[
                            tower_index
                        ][
                            component_index
                        ]
                    ),
                    .result       (
                        multiplier_result[
                            tower_index
                        ][
                            component_index
                        ]
                    )
                );
            end
        end
    endgenerate

    wire result_valid =
        &multiplier_output_valid;

    /*
     * Results preserve launch order, so one result-side digit counter is
     * sufficient even while several modular products are in flight.
     */
    logic [DIGIT_WIDTH-1:0] result_digit_index;

    logic [1:0][31:0] accumulator_b;
    logic [1:0][31:0] accumulator_a;

    logic [1:0][32:0] accumulated_b_extended;
    logic [1:0][32:0] accumulated_a_extended;

    logic [1:0][31:0] accumulated_b_reduced;
    logic [1:0][31:0] accumulated_a_reduced;

    /*
     * Explicit packed lanes avoid Icarus treating a procedural loop index as
     * a non-constant packed-array selector.
     */
    always @*
    begin
        accumulated_b_extended[0] =
            {
                1'b0,
                accumulator_b[0]
            }
            + {
                1'b0,
                multiplier_result[0][0]
            };

        accumulated_a_extended[0] =
            {
                1'b0,
                accumulator_a[0]
            }
            + {
                1'b0,
                multiplier_result[0][1]
            };

        accumulated_b_reduced[0] =
            accumulated_b_extended[0]
                >= {
                    1'b0,
                    modulus_lane[0]
                }
            ? accumulated_b_extended[0][31:0]
                - modulus_lane[0]
            : accumulated_b_extended[0][31:0];

        accumulated_a_reduced[0] =
            accumulated_a_extended[0]
                >= {
                    1'b0,
                    modulus_lane[0]
                }
            ? accumulated_a_extended[0][31:0]
                - modulus_lane[0]
            : accumulated_a_extended[0][31:0];

        accumulated_b_extended[1] =
            {
                1'b0,
                accumulator_b[1]
            }
            + {
                1'b0,
                multiplier_result[1][0]
            };

        accumulated_a_extended[1] =
            {
                1'b0,
                accumulator_a[1]
            }
            + {
                1'b0,
                multiplier_result[1][1]
            };

        accumulated_b_reduced[1] =
            accumulated_b_extended[1]
                >= {
                    1'b0,
                    modulus_lane[1]
                }
            ? accumulated_b_extended[1][31:0]
                - modulus_lane[1]
            : accumulated_b_extended[1][31:0];

        accumulated_a_reduced[1] =
            accumulated_a_extended[1]
                >= {
                    1'b0,
                    modulus_lane[1]
                }
            ? accumulated_a_extended[1][31:0]
                - modulus_lane[1]
            : accumulated_a_extended[1][31:0];
    end

    wire result_first_digit =
        result_digit_index == 0;

    wire result_final_digit =
        result_digit_index + 1'b1 == digit_count;

    wire coefficient_result_valid =
        result_valid
        && result_final_digit;

    wire [63:0] completed_ks_b = {
        result_first_digit
            ? multiplier_result[1][0]
            : accumulated_b_reduced[1],
        result_first_digit
            ? multiplier_result[0][0]
            : accumulated_b_reduced[0]
    };

    wire [63:0] completed_ks_a = {
        result_first_digit
            ? multiplier_result[1][1]
            : accumulated_a_reduced[1],
        result_first_digit
            ? multiplier_result[0][1]
            : accumulated_a_reduced[0]
    };

    /*
     * Each FIFO entry is one coefficient's two key-switch contribution words.
     */
    logic [63:0] fifo_ks_b [0:FIFO_DEPTH-1];
    logic [63:0] fifo_ks_a [0:FIFO_DEPTH-1];

    logic [FIFO_PTR_WIDTH-1:0] fifo_write_pointer;
    logic [FIFO_PTR_WIDTH-1:0] fifo_read_pointer;

    logic output_component;
    logic [31:0] output_ciphertext_index;
    logic [INDEX_WIDTH-1:0] output_coefficient_index;

    assign m_axis_tvalid =
        fifo_count != 0;

    /*
     * Do not evaluate a dynamic FIFO memory read until reset is complete and
     * an entry is valid. AXI TDATA is don't-care while TVALID is low.
     */
    assign m_axis_tdata =
        !reset_n || fifo_count == 0
        ? 64'd0
        : output_component
        ? fifo_ks_a[fifo_read_pointer]
        : fifo_ks_b[fifo_read_pointer];

    wire final_output_word =
        output_component
        && output_coefficient_index == LAST_COEFFICIENT
        && output_ciphertext_index + 1'b1 == batch_count;

    assign m_axis_tlast =
        m_axis_tvalid
        && final_output_word;

    wire release_result_slot =
        output_handshake
        && output_component;

    wire batch_output_complete =
        release_result_slot
        && final_output_word;

    assign accelerator_busy =
        input_state != INPUT_IDLE
        || reserved_count != 0
        || fifo_count != 0;

    /*
     * Input protocol and operand capture.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            input_state <=
                INPUT_IDLE;

            modulus_register <=
                64'd0;

            mu_register <=
                62'd0;

            profile_ready <=
                1'b0;

            protocol_error <=
                1'b0;

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

            input_digit_index <=
                '0;

            input_operand_phase <=
                2'd0;

            operand_digit <=
                64'd0;

            operand_key_b <=
                64'd0;

            completed_profiles <=
                32'd0;

            launched_digit_products <=
                32'd0;
        end
        else
        begin
            if (
                input_state == INPUT_WAIT_COMPLETE
                && batch_output_complete
            )
            begin
                input_state <=
                    INPUT_IDLE;
            end

            case (input_state)
                INPUT_IDLE:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;
                        end
                        else if (profile_command)
                        begin
                            input_state <=
                                INPUT_PROFILE_Q;
                        end
                        else if (
                            mac_command
                            && profile_ready
                        )
                        begin
                            input_state <=
                                INPUT_BATCH_HEADER;
                        end
                        else
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_DISCARD;
                        end
                    end
                end

                INPUT_PROFILE_Q:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:30] != 2'b00
                            || s_axis_tdata[63:62] != 2'b00
                            || !s_axis_tdata[29]
                            || !s_axis_tdata[61]
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                s_axis_tlast
                                    ? INPUT_IDLE
                                    : INPUT_DISCARD;
                        end
                        else
                        begin
                            modulus_register <=
                                s_axis_tdata;

                            input_state <=
                                INPUT_PROFILE_MU;
                        end
                    end
                end

                INPUT_PROFILE_MU:
                begin
                    if (input_handshake)
                    begin
                        if (
                            !s_axis_tlast
                            || s_axis_tdata[31]
                            || s_axis_tdata[63]
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                s_axis_tlast
                                    ? INPUT_IDLE
                                    : INPUT_DISCARD;
                        end
                        else
                        begin
                            mu_register <= {
                                s_axis_tdata[62:32],
                                s_axis_tdata[30:0]
                            };

                            profile_ready <=
                                1'b1;

                            completed_profiles <=
                                completed_profiles + 1'b1;

                            input_state <=
                                INPUT_IDLE;
                        end
                    end
                end

                INPUT_BATCH_HEADER:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:0] == 32'd0
                            || s_axis_tdata[63:32] == 32'd0
                            || s_axis_tdata[63:32] > MAX_DIGITS
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                s_axis_tlast
                                    ? INPUT_IDLE
                                    : INPUT_DISCARD;
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

                            input_digit_index <=
                                '0;

                            input_operand_phase <=
                                2'd0;

                            input_state <=
                                INPUT_DATA;
                        end
                    end
                end

                INPUT_DATA:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            != final_input_word
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                s_axis_tlast
                                    ? INPUT_IDLE
                                    : INPUT_DISCARD;
                        end
                        else
                        begin
                            case (input_operand_phase)
                                2'd0:
                                begin
                                    operand_digit <=
                                        s_axis_tdata;

                                    input_operand_phase <=
                                        2'd1;
                                end

                                2'd1:
                                begin
                                    operand_key_b <=
                                        s_axis_tdata;

                                    input_operand_phase <=
                                        2'd2;
                                end

                                default:
                                begin
                                    launched_digit_products <=
                                        launched_digit_products + 1'b1;

                                    input_operand_phase <=
                                        2'd0;

                                    if (final_digit_input)
                                    begin
                                        input_digit_index <=
                                            '0;

                                        if (
                                            input_coefficient_index
                                            == LAST_COEFFICIENT
                                        )
                                        begin
                                            input_coefficient_index <=
                                                '0;

                                            if (final_input_word)
                                            begin
                                                input_state <=
                                                    INPUT_WAIT_COMPLETE;
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
                                        input_digit_index <=
                                            input_digit_index + 1'b1;
                                    end
                                end
                            endcase
                        end
                    end
                end

                INPUT_DISCARD:
                begin
                    if (
                        input_handshake
                        && s_axis_tlast
                    )
                    begin
                        input_state <=
                            INPUT_IDLE;
                    end
                end

                default:
                begin
                end
            endcase
        end
    end

    /*
     * Ordered modular accumulation of the digit products.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            result_digit_index <=
                '0;

            accumulator_b <=
                '0;

            accumulator_a <=
                '0;

            completed_coefficients <=
                32'd0;
        end
        else if (batch_header_accepted)
        begin
            result_digit_index <=
                '0;

            accumulator_b <=
                '0;

            accumulator_a <=
                '0;
        end
        else if (result_valid)
        begin
            if (result_first_digit)
            begin
                accumulator_b[0] <=
                    multiplier_result[0][0];

                accumulator_b[1] <=
                    multiplier_result[1][0];

                accumulator_a[0] <=
                    multiplier_result[0][1];

                accumulator_a[1] <=
                    multiplier_result[1][1];
            end
            else
            begin
                accumulator_b <=
                    accumulated_b_reduced;

                accumulator_a <=
                    accumulated_a_reduced;
            end

            if (result_final_digit)
            begin
                result_digit_index <=
                    '0;

                completed_coefficients <=
                    completed_coefficients + 1'b1;
            end
            else
            begin
                result_digit_index <=
                    result_digit_index + 1'b1;
            end
        end
    end

    /*
     * Completed-result FIFO occupancy.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            fifo_count <=
                '0;

            fifo_write_pointer <=
                '0;

            fifo_read_pointer <=
                '0;
        end
        else
        begin
            case ({
                coefficient_result_valid,
                release_result_slot
            })
                2'b10:
                begin
                    fifo_count <=
                        fifo_count + 1'b1;
                end

                2'b01:
                begin
                    fifo_count <=
                        fifo_count - 1'b1;
                end

                default:
                begin
                end
            endcase

            if (coefficient_result_valid)
            begin
                fifo_ks_b[fifo_write_pointer] <=
                    completed_ks_b;

                fifo_ks_a[fifo_write_pointer] <=
                    completed_ks_a;

                fifo_write_pointer <=
                    fifo_write_pointer + 1'b1;
            end

            if (release_result_slot)
            begin
                fifo_read_pointer <=
                    fifo_read_pointer + 1'b1;
            end
        end
    end

    /*
     * Reserved entries include active coefficients, multiplier results in
     * flight, completed FIFO entries, and partially emitted output entries.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            reserved_count <=
                '0;
        end
        else
        begin
            case ({
                reserve_result_slot,
                release_result_slot
            })
                2'b10:
                begin
                    reserved_count <=
                        reserved_count + 1'b1;
                end

                2'b01:
                begin
                    reserved_count <=
                        reserved_count - 1'b1;
                end

                default:
                begin
                end
            endcase
        end
    end

    /*
     * Output framing and completion counters.
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
        end
        else
        begin
            if (batch_header_accepted)
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
                                output_ciphertext_index + 1'b1;
                        end
                    end
                    else
                    begin
                        output_coefficient_index <=
                            output_coefficient_index + 1'b1;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS

    localparam logic [63:0] BARRETT_SCALE =
        64'h1000000000000000;

    always @(posedge clk)
    begin
        if (reset_n)
        begin
            if (
                (|multiplier_output_valid)
                && !(&multiplier_output_valid)
            )
            begin
                $display(
                    "ERROR: BV key-switch multiplier lanes left lockstep: %b",
                    multiplier_output_valid
                );

                $fatal(1);
            end

            if (
                coefficient_result_valid
                && reserved_count == 0
            )
            begin
                $display(
                    "ERROR: BV key-switch result arrived without a reservation"
                );

                $fatal(1);
            end

            if (
                coefficient_result_valid
                && fifo_count == FIFO_DEPTH
                && !release_result_slot
            )
            begin
                $display(
                    "ERROR: BV key-switch result FIFO overflow"
                );

                $fatal(1);
            end

            if (
                release_result_slot
                && fifo_count == 0
            )
            begin
                $display(
                    "ERROR: BV key-switch result FIFO underflow"
                );

                $fatal(1);
            end

            if (
                input_state == INPUT_PROFILE_MU
                && input_handshake
                && s_axis_tlast
                && !s_axis_tdata[31]
                && !s_axis_tdata[63]
            )
            begin
                if (
                    s_axis_tdata[30:0]
                    != BARRETT_SCALE
                        / modulus_register[31:0]
                    || s_axis_tdata[62:32]
                    != BARRETT_SCALE
                        / modulus_register[63:32]
                )
                begin
                    $display(
                        "ERROR: incorrect BV key-switch Barrett reciprocal"
                    );

                    $fatal(1);
                end
            end
        end
    end

    initial
    begin
        if (N < 2 || (N & (N - 1)) != 0)
        begin
            $display(
                "ERROR: BV key-switch MAC requires power-of-two N >= 2"
            );

            $fatal(1);
        end

        if (
            MAX_DIGITS < 1
            || (MAX_DIGITS & (MAX_DIGITS - 1)) != 0
        )
        begin
            $display(
                "ERROR: BV key-switch MAC requires power-of-two MAX_DIGITS"
            );

            $fatal(1);
        end

        if (
            FIFO_DEPTH < 4
            || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0
        )
        begin
            $display(
                "ERROR: BV key-switch MAC requires power-of-two FIFO_DEPTH >= 4"
            );

            $fatal(1);
        end
    end

`endif

endmodule
