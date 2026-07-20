`timescale 1ns/1ps

/*
 * AXI4-Stream command adapter for the runtime-profile N=4096
 * dual-butterfly polynomial multiplier.
 *
 * Input command frames:
 *
 *   PROFILE frame:
 *
 *     word 0      0x50524f46  ("PROF")
 *     word 1      modulus q
 *     words 2..4097
 *                 4096 twist factors
 *     words 4098..8192
 *                 4095 forward twiddles
 *     words 8193..12287
 *                 4095 inverse twiddles
 *     words 12288..16383
 *                 4096 inverse-scale factors
 *
 *     Total: 16384 words / 65536 bytes.
 *
 *   PRODUCT frame:
 *
 *     word 0      0x4d554c31  ("MUL1")
 *     words 1..4096
 *                 A[0..4095]
 *     words 4097..8192
 *                 B[0..4095]
 *
 *     Total: 8193 words / 32772 bytes.
 *
 * Output for each successful PRODUCT frame:
 *
 *     C[0..4095], 4096 words / 16384 bytes.
 *
 * TLAST is required only on the final word of each input frame and
 * the final result coefficient.
 */
module poly_mul4096_dual_butterfly_runtime_profile_axis_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic [31:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    output logic        protocol_error,
    output logic        profile_ready,
    output logic [31:0] active_modulus,

    output logic [31:0] completed_profiles,
    output logic [31:0] completed_products,

    output logic [31:0] profile_words_received,
    output logic [31:0] product_words_received,

    output logic        accelerator_busy,
    output logic [31:0] core_cycles,
    output logic [16:0] modular_multiplications
);

    localparam logic [31:0] COMMAND_PROFILE =
        32'h50524f46;

    localparam logic [31:0] COMMAND_PRODUCT =
        32'h4d554c31;

    localparam integer N =
        4096;

    localparam integer PROFILE_PAYLOAD_WORDS =
        16382;

    localparam integer PROFILE_FORWARD_BASE =
        4096;

    localparam integer PROFILE_INVERSE_BASE =
        8191;

    localparam integer PROFILE_SCALE_BASE =
        12286;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PROFILE_MODULUS,
        STATE_PROFILE_PAYLOAD,
        STATE_PROFILE_COMMIT,
        STATE_PRODUCT_A,
        STATE_PRODUCT_B,
        STATE_PRODUCT_START,
        STATE_PRODUCT_WAIT,
        STATE_OUTPUT_ISSUE,
        STATE_OUTPUT_SEND,
        STATE_DISCARD
    } state_t;

    state_t state;

    logic [13:0] profile_index;
    logic [11:0] product_index;
    logic [11:0] output_index;

    logic input_handshake;
    logic output_handshake;

    logic core_start;

    logic core_load_a_we;
    logic [11:0] core_load_a_addr;
    logic [31:0] core_load_a_data;

    logic core_load_b_we;
    logic [11:0] core_load_b_addr;
    logic [31:0] core_load_b_data;

    logic [11:0] core_read_a_addr;
    logic [31:0] core_read_a_data;

    logic [31:0] unused_read_b_data;

    logic core_profile_modulus_we;
    logic [31:0] core_profile_modulus_data;

    logic core_profile_we;
    logic [1:0] core_profile_bank;
    logic [11:0] core_profile_addr;
    logic [31:0] core_profile_data;

    logic core_profile_commit;

    logic core_busy;
    logic core_done;

    logic [13:0] unused_preprocessing_count;
    logic [15:0] unused_forward_butterfly_count;
    logic [12:0] unused_pointwise_count;
    logic [14:0] unused_inverse_butterfly_count;
    logic [12:0] unused_postprocessing_count;

    assign input_handshake =
        s_axis_tvalid
        && s_axis_tready;

    assign output_handshake =
        m_axis_tvalid
        && m_axis_tready;

    assign accelerator_busy =
        core_busy
        || state != STATE_IDLE;

    always_comb
    begin
        s_axis_tready =
            1'b0;

        case (state)
            STATE_IDLE,
            STATE_PROFILE_MODULUS,
            STATE_PROFILE_PAYLOAD,
            STATE_PRODUCT_A,
            STATE_PRODUCT_B,
            STATE_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            default:
            begin
            end
        endcase
    end

    assign core_start =
        state == STATE_PRODUCT_START;

    assign core_profile_commit =
        state == STATE_PROFILE_COMMIT;

    assign core_profile_modulus_we =
        input_handshake
        && state == STATE_PROFILE_MODULUS;

    assign core_profile_modulus_data =
        s_axis_tdata;

    assign core_profile_we =
        input_handshake
        && state == STATE_PROFILE_PAYLOAD;

    assign core_profile_data =
        s_axis_tdata;

    always_comb
    begin
        core_profile_bank =
            2'd0;

        core_profile_addr =
            12'd0;

        if (profile_index < PROFILE_FORWARD_BASE)
        begin
            core_profile_bank =
                2'd0;

            core_profile_addr =
                profile_index[11:0];
        end
        else if (profile_index < PROFILE_INVERSE_BASE)
        begin
            core_profile_bank =
                2'd1;

            core_profile_addr =
                profile_index - PROFILE_FORWARD_BASE;
        end
        else if (profile_index < PROFILE_SCALE_BASE)
        begin
            core_profile_bank =
                2'd2;

            core_profile_addr =
                profile_index - PROFILE_INVERSE_BASE;
        end
        else
        begin
            core_profile_bank =
                2'd3;

            core_profile_addr =
                profile_index - PROFILE_SCALE_BASE;
        end
    end

    assign core_load_a_we =
        input_handshake
        && state == STATE_PRODUCT_A;

    assign core_load_a_addr =
        product_index;

    assign core_load_a_data =
        s_axis_tdata;

    assign core_load_b_we =
        input_handshake
        && state == STATE_PRODUCT_B;

    assign core_load_b_addr =
        product_index;

    assign core_load_b_data =
        s_axis_tdata;

    assign core_read_a_addr =
        output_index;

    assign m_axis_tdata =
        core_read_a_data;

    assign m_axis_tvalid =
        state == STATE_OUTPUT_SEND;

    assign m_axis_tlast =
        state == STATE_OUTPUT_SEND
        && output_index == 12'd4095;

    poly_mul4096_dual_butterfly_runtime_profile_core core (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (core_start),

        .load_a_we                 (core_load_a_we),
        .load_a_addr               (core_load_a_addr),
        .load_a_data               (core_load_a_data),

        .load_b_we                 (core_load_b_we),
        .load_b_addr               (core_load_b_addr),
        .load_b_data               (core_load_b_data),

        .read_a_addr               (core_read_a_addr),
        .read_a_data               (core_read_a_data),

        .read_b_addr               (12'd0),
        .read_b_data               (unused_read_b_data),

        .profile_modulus_we        (core_profile_modulus_we),
        .profile_modulus_data      (core_profile_modulus_data),

        .profile_we                (core_profile_we),
        .profile_bank              (core_profile_bank),
        .profile_addr              (core_profile_addr),
        .profile_data              (core_profile_data),

        .profile_commit            (core_profile_commit),

        .profile_ready             (profile_ready),
        .active_modulus            (active_modulus),

        .busy                      (core_busy),
        .done                      (core_done),

        .cycles                    (core_cycles),
        .multiplication_count      (modular_multiplications),

        .preprocessing_count       (unused_preprocessing_count),
        .forward_butterfly_count   (unused_forward_butterfly_count),
        .pointwise_count           (unused_pointwise_count),
        .inverse_butterfly_count   (unused_inverse_butterfly_count),
        .postprocessing_count      (unused_postprocessing_count)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            profile_index <=
                14'd0;

            product_index <=
                12'd0;

            output_index <=
                12'd0;

            protocol_error <=
                1'b0;

            completed_profiles <=
                32'd0;

            completed_products <=
                32'd0;

            profile_words_received <=
                32'd0;

            product_words_received <=
                32'd0;
        end
        else
        begin
            case (state)
                STATE_IDLE:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;
                        end
                        else if (s_axis_tdata == COMMAND_PROFILE)
                        begin
                            state <=
                                STATE_PROFILE_MODULUS;

                            profile_index <=
                                14'd0;

                            profile_words_received <=
                                32'd0;
                        end
                        else if (s_axis_tdata == COMMAND_PRODUCT)
                        begin
                            product_index <=
                                12'd0;

                            product_words_received <=
                                32'd0;

                            if (profile_ready)
                            begin
                                state <=
                                    STATE_PRODUCT_A;
                            end
                            else
                            begin
                                protocol_error <=
                                    1'b1;

                                state <=
                                    STATE_DISCARD;
                            end
                        end
                        else
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_DISCARD;
                        end
                    end
                end

                STATE_PROFILE_MODULUS:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            state <=
                                STATE_PROFILE_PAYLOAD;
                        end
                    end
                end

                STATE_PROFILE_PAYLOAD:
                begin
                    if (input_handshake)
                    begin
                        profile_words_received <=
                            profile_words_received + 1'b1;

                        if (
                            profile_index
                            == PROFILE_PAYLOAD_WORDS - 1
                        )
                        begin
                            if (s_axis_tlast)
                            begin
                                state <=
                                    STATE_PROFILE_COMMIT;
                            end
                            else
                            begin
                                protocol_error <=
                                    1'b1;

                                state <=
                                    STATE_DISCARD;
                            end
                        end
                        else if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            profile_index <=
                                profile_index + 1'b1;
                        end
                    end
                end

                STATE_PROFILE_COMMIT:
                begin
                    completed_profiles <=
                        completed_profiles + 1'b1;

                    state <=
                        STATE_IDLE;
                end

                STATE_PRODUCT_A:
                begin
                    if (input_handshake)
                    begin
                        product_words_received <=
                            product_words_received + 1'b1;

                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else if (product_index == 12'd4095)
                        begin
                            product_index <=
                                12'd0;

                            state <=
                                STATE_PRODUCT_B;
                        end
                        else
                        begin
                            product_index <=
                                product_index + 1'b1;
                        end
                    end
                end

                STATE_PRODUCT_B:
                begin
                    if (input_handshake)
                    begin
                        product_words_received <=
                            product_words_received + 1'b1;

                        if (product_index == 12'd4095)
                        begin
                            if (s_axis_tlast)
                            begin
                                state <=
                                    STATE_PRODUCT_START;
                            end
                            else
                            begin
                                protocol_error <=
                                    1'b1;

                                state <=
                                    STATE_DISCARD;
                            end
                        end
                        else if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            product_index <=
                                product_index + 1'b1;
                        end
                    end
                end

                STATE_PRODUCT_START:
                begin
                    state <=
                        STATE_PRODUCT_WAIT;
                end

                STATE_PRODUCT_WAIT:
                begin
                    if (core_done)
                    begin
                        output_index <=
                            12'd0;

                        state <=
                            STATE_OUTPUT_ISSUE;
                    end
                end

                STATE_OUTPUT_ISSUE:
                begin
                    state <=
                        STATE_OUTPUT_SEND;
                end

                STATE_OUTPUT_SEND:
                begin
                    if (output_handshake)
                    begin
                        if (output_index == 12'd4095)
                        begin
                            completed_products <=
                                completed_products + 1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else
                        begin
                            output_index <=
                                output_index + 1'b1;

                            state <=
                                STATE_OUTPUT_ISSUE;
                        end
                    end
                end

                STATE_DISCARD:
                begin
                    if (input_handshake && s_axis_tlast)
                    begin
                        state <=
                            STATE_IDLE;
                    end
                end

                default:
                begin
                    state <=
                        STATE_IDLE;

                    protocol_error <=
                        1'b1;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            reset_n
            && core_start
            && !profile_ready
        )
        begin
            $display(
                "ERROR: AXI runtime-profile adapter started without a committed profile"
            );

            $fatal(1);
        end

        if (
            reset_n
            && core_load_a_we
            && core_busy
        )
        begin
            $display(
                "ERROR: AXI runtime-profile adapter wrote A while the core was busy"
            );

            $fatal(1);
        end

        if (
            reset_n
            && core_load_b_we
            && core_busy
        )
        begin
            $display(
                "ERROR: AXI runtime-profile adapter wrote B while the core was busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
