`timescale 1ns/1ps

/*
 * Fused two-tower evaluation-domain ciphertext multiplication.
 *
 * Input and output words are paired RNS towers:
 *
 *     bits 31:0  = tower lane 0
 *     bits 63:32 = tower lane 1
 *
 * Profile frame:
 *
 *     word 0: { "EVPF", "EVPF" }
 *     word 1: { q1, q0 }
 *     word 2: { mu1, mu0 }, TLAST=1
 *
 * where mu = floor(2^60/q), carried in 31 bits.
 *
 * Batch frame:
 *
 *     word 0: { "EVB3", "EVB3" }
 *     word 1: { count, count }
 *
 *     for each ciphertext and each evaluation-domain coefficient:
 *
 *         a0
 *         a1
 *         b0
 *         b1
 *
 * The four products are launched together:
 *
 *     p00 = a0*b0
 *     p01 = a0*b1
 *     p10 = a1*b0
 *     p11 = a1*b1
 *
 * Output order for every coefficient:
 *
 *     c0 = p00
 *     c1 = p01+p10 mod q
 *     c2 = p11
 *
 * No NTT, inverse NTT, twiddle memory, or coefficient BRAM is used.
 *
 * With an unstalled 64-bit AXI stream, one ciphertext consumes 4*N input
 * clocks and produces 3*N output clocks. Input bandwidth is therefore the
 * steady-state limit.
 */
module evalmul3_two_tower_axis_core #(
    parameter integer N = 4096,
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
    output logic [31:0] completed_profiles,
    output logic [31:0] completed_ciphertexts,
    output logic [31:0] completed_batches,
    output logic [31:0] launched_coefficients
);

    localparam integer INDEX_WIDTH =
        (N <= 2) ? 1 : $clog2(N);

    localparam integer FIFO_PTR_WIDTH =
        (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);

    localparam logic [INDEX_WIDTH-1:0] LAST_COEFFICIENT =
        N - 1;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h45565046;  // "EVPF"

    localparam logic [31:0] COMMAND_BATCH =
        32'h45564233;  // "EVB3"

    typedef enum logic [2:0] {
        INPUT_IDLE,
        INPUT_PROFILE_Q,
        INPUT_PROFILE_MU,
        INPUT_BATCH_COUNT,
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
    logic [31:0] input_ciphertext_index;
    logic [INDEX_WIDTH-1:0] input_coefficient_index;
    logic [1:0] input_operand_phase;

    logic [63:0] operand_a0;
    logic [63:0] operand_a1;
    logic [63:0] operand_b0;

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

    wire batch_command =
        s_axis_tdata == {
            COMMAND_BATCH,
            COMMAND_BATCH
        };

    wire batch_count_accepted =
        input_handshake
        && input_state == INPUT_BATCH_COUNT
        && !s_axis_tlast
        && s_axis_tdata[31:0] != 32'd0
        && s_axis_tdata[63:32] == s_axis_tdata[31:0];

    wire final_input_word =
        input_state == INPUT_DATA
        && input_operand_phase == 2'd3
        && input_coefficient_index == LAST_COEFFICIENT
        && input_ciphertext_index + 1'b1 == batch_count;

    wire reserve_result_slot =
        input_handshake
        && input_state == INPUT_DATA
        && input_operand_phase == 2'd0;

    wire launch_valid =
        input_handshake
        && input_state == INPUT_DATA
        && input_operand_phase == 2'd3;

    /*
     * Reserve FIFO capacity when a0 is accepted, before the associated
     * multiplier result exists. This bounds completed plus in-flight
     * triples under arbitrary output backpressure.
     */
    logic [FIFO_PTR_WIDTH:0] reserved_count;
    logic [FIFO_PTR_WIDTH:0] fifo_count;

    wire fifo_has_credit =
        reserved_count < FIFO_DEPTH;

    always_comb
    begin
        s_axis_tready =
            1'b0;

        case (input_state)
            INPUT_IDLE,
            INPUT_PROFILE_Q,
            INPUT_PROFILE_MU,
            INPUT_BATCH_COUNT,
            INPUT_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            INPUT_DATA:
            begin
                s_axis_tready =
                    input_operand_phase != 2'd0
                    || fifo_has_credit;
            end

            default:
            begin
            end
        endcase
    end

    /*
     * Two towers, four products per tower.
     */
    logic [1:0][3:0][31:0] multiplier_a;
    logic [1:0][3:0][31:0] multiplier_b;
    logic [1:0][3:0][31:0] multiplier_result;
    logic [1:0][3:0]       multiplier_output_valid;

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
     * Keep the tower extraction explicitly unrolled.
     *
     * Icarus Verilog treats a variable-select into a packed multidimensional
     * array as a constant-expression context. Vivado accepts the loop form,
     * but Icarus rejects it during elaboration. These assignments are exactly
     * the same circuit and are portable across both tools.
     */
    always_comb
    begin
        multiplier_a =
            '0;

        multiplier_b =
            '0;

        multiplier_a[0][0] =
            operand_a0[31:0];

        multiplier_b[0][0] =
            operand_b0[31:0];

        multiplier_a[0][1] =
            operand_a0[31:0];

        multiplier_b[0][1] =
            s_axis_tdata[31:0];

        multiplier_a[0][2] =
            operand_a1[31:0];

        multiplier_b[0][2] =
            operand_b0[31:0];

        multiplier_a[0][3] =
            operand_a1[31:0];

        multiplier_b[0][3] =
            s_axis_tdata[31:0];

        multiplier_a[1][0] =
            operand_a0[63:32];

        multiplier_b[1][0] =
            operand_b0[63:32];

        multiplier_a[1][1] =
            operand_a0[63:32];

        multiplier_b[1][1] =
            s_axis_tdata[63:32];

        multiplier_a[1][2] =
            operand_a1[63:32];

        multiplier_b[1][2] =
            operand_b0[63:32];

        multiplier_a[1][3] =
            operand_a1[63:32];

        multiplier_b[1][3] =
            s_axis_tdata[63:32];
    end

    generate
        genvar tower_index;
        genvar product_index;

        for (
            tower_index = 0;
            tower_index < 2;
            tower_index = tower_index + 1
        )
        begin : multiplier_towers
            for (
                product_index = 0;
                product_index < 4;
                product_index = product_index + 1
            )
            begin : multiplier_products
                modmul_barrett60_pipeline_split_core multiplier (
                    .clk          (clk),
                    .reset_n      (reset_n),
                    .input_valid  (launch_valid),
                    .a            (
                        multiplier_a[
                            tower_index
                        ][
                            product_index
                        ]
                    ),
                    .b            (
                        multiplier_b[
                            tower_index
                        ][
                            product_index
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
                            product_index
                        ]
                    ),
                    .result       (
                        multiplier_result[
                            tower_index
                        ][
                            product_index
                        ]
                    )
                );
            end
        end
    endgenerate

    wire result_valid =
        &multiplier_output_valid;

    logic [1:0][32:0] middle_sum_extended;
    logic [1:0][31:0] middle_sum_reduced;

    /*
     * Explicit tower equations avoid the same Icarus limitation on
     * variable indices into packed multidimensional arrays.
     */
    always_comb
    begin
        middle_sum_extended[0] =
            {
                1'b0,
                multiplier_result[0][1]
            }
            + {
                1'b0,
                multiplier_result[0][2]
            };

        middle_sum_reduced[0] =
            middle_sum_extended[0]
                >= {
                    1'b0,
                    modulus_lane[0]
                }
            ? middle_sum_extended[0][31:0]
                - modulus_lane[0]
            : middle_sum_extended[0][31:0];

        middle_sum_extended[1] =
            {
                1'b0,
                multiplier_result[1][1]
            }
            + {
                1'b0,
                multiplier_result[1][2]
            };

        middle_sum_reduced[1] =
            middle_sum_extended[1]
                >= {
                    1'b0,
                    modulus_lane[1]
                }
            ? middle_sum_extended[1][31:0]
                - modulus_lane[1]
            : middle_sum_extended[1][31:0];
    end

    wire [63:0] completed_c0 = {
        multiplier_result[1][0],
        multiplier_result[0][0]
    };

    wire [63:0] completed_c1 = {
        middle_sum_reduced[1],
        middle_sum_reduced[0]
    };

    wire [63:0] completed_c2 = {
        multiplier_result[1][3],
        multiplier_result[0][3]
    };

    /*
     * Small result FIFO. Each entry is one coefficient triple.
     */
    logic [63:0] fifo_c0 [0:FIFO_DEPTH-1];
    logic [63:0] fifo_c1 [0:FIFO_DEPTH-1];
    logic [63:0] fifo_c2 [0:FIFO_DEPTH-1];

    logic [FIFO_PTR_WIDTH-1:0] fifo_write_pointer;
    logic [FIFO_PTR_WIDTH-1:0] fifo_read_pointer;

    logic [1:0] output_component;
    logic [31:0] output_ciphertext_index;
    logic [INDEX_WIDTH-1:0] output_coefficient_index;

    assign m_axis_tvalid =
        fifo_count != 0;

    always_comb
    begin
        case (output_component)
            2'd0:
            begin
                m_axis_tdata =
                    fifo_c0[fifo_read_pointer];
            end

            2'd1:
            begin
                m_axis_tdata =
                    fifo_c1[fifo_read_pointer];
            end

            default:
            begin
                m_axis_tdata =
                    fifo_c2[fifo_read_pointer];
            end
        endcase
    end

    wire final_output_word =
        output_component == 2'd2
        && output_coefficient_index == LAST_COEFFICIENT
        && output_ciphertext_index + 1'b1 == batch_count;

    assign m_axis_tlast =
        m_axis_tvalid
        && final_output_word;

    wire release_result_slot =
        output_handshake
        && output_component == 2'd2;

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

            active_batch_size <=
                32'd0;

            input_ciphertext_index <=
                32'd0;

            input_coefficient_index <=
                '0;

            input_operand_phase <=
                2'd0;

            operand_a0 <=
                64'd0;

            operand_a1 <=
                64'd0;

            operand_b0 <=
                64'd0;

            completed_profiles <=
                32'd0;

            launched_coefficients <=
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
                            batch_command
                            && profile_ready
                        )
                        begin
                            input_state <=
                                INPUT_BATCH_COUNT;
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

                INPUT_BATCH_COUNT:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[31:0] == 32'd0
                            || s_axis_tdata[63:32]
                                != s_axis_tdata[31:0]
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

                            active_batch_size <=
                                s_axis_tdata[31:0];

                            input_ciphertext_index <=
                                32'd0;

                            input_coefficient_index <=
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
                                    operand_a0 <=
                                        s_axis_tdata;

                                    input_operand_phase <=
                                        2'd1;
                                end

                                2'd1:
                                begin
                                    operand_a1 <=
                                        s_axis_tdata;

                                    input_operand_phase <=
                                        2'd2;
                                end

                                2'd2:
                                begin
                                    operand_b0 <=
                                        s_axis_tdata;

                                    input_operand_phase <=
                                        2'd3;
                                end

                                default:
                                begin
                                    launched_coefficients <=
                                        launched_coefficients + 1'b1;

                                    input_operand_phase <=
                                        2'd0;

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
     * FIFO occupancy includes only completed multiplier results.
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
                result_valid,
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

            if (result_valid)
            begin
                fifo_c0[fifo_write_pointer] <=
                    completed_c0;

                fifo_c1[fifo_write_pointer] <=
                    completed_c1;

                fifo_c2[fifo_write_pointer] <=
                    completed_c2;

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
     * Reserved entries include both completed FIFO entries and
     * multiplier results still in flight.
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
                2'd0;

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
            if (batch_count_accepted)
            begin
                output_component <=
                    2'd0;

                output_ciphertext_index <=
                    32'd0;

                output_coefficient_index <=
                    '0;
            end
            else if (output_handshake)
            begin
                if (output_component != 2'd2)
                begin
                    output_component <=
                        output_component + 1'b1;
                end
                else
                begin
                    output_component <=
                        2'd0;

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
                    "ERROR: fused multiplier lanes left lockstep: %b",
                    multiplier_output_valid
                );

                $fatal(1);
            end

            if (
                result_valid
                && reserved_count == 0
            )
            begin
                $display(
                    "ERROR: multiplier result arrived without a reserved FIFO slot"
                );

                $fatal(1);
            end

            if (
                result_valid
                && fifo_count == FIFO_DEPTH
                && !release_result_slot
            )
            begin
                $display(
                    "ERROR: fused result FIFO overflow"
                );

                $fatal(1);
            end

            if (
                release_result_slot
                && fifo_count == 0
            )
            begin
                $display(
                    "ERROR: fused result FIFO underflow"
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
                        "ERROR: incorrect fused evaluation profile reciprocal"
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
                "ERROR: evalmul3 requires power-of-two N >= 2"
            );

            $fatal(1);
        end

        if (
            FIFO_DEPTH < 4
            || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0
        )
        begin
            $display(
                "ERROR: evalmul3 requires power-of-two FIFO_DEPTH >= 4"
            );

            $fatal(1);
        end
    end

`endif

endmodule
