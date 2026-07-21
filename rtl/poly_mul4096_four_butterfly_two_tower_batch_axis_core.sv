`timescale 1ns/1ps

/*
 * Batched 64-bit AXI4-Stream adapter for the lockstep two-tower,
 * four-butterfly N=4096 negacyclic multiplier.
 *
 * Stream word packing:
 *
 *     bits 31:0  = tower 0
 *     bits 63:32 = tower 1
 *
 * Profile frame (unchanged from the direct checkpoint):
 *
 *     word 0: repeated 0x50524f46 ("PROF")
 *     word 1: paired moduli
 *     word 2: paired Barrett reciprocals floor(2^60 / q)
 *     words 3..16384: paired profile payload
 *     TLAST on word 16384
 *
 * Single-product frame:
 *
 *     word 0: repeated 0x4d554c31 ("MUL1")
 *     4096 paired A coefficients
 *     4096 paired B coefficients
 *     TLAST on the final B coefficient
 *
 * Batch frame:
 *
 *     word 0: repeated 0x4d554c42 ("MULB")
 *     word 1: batch count repeated in both 32-bit lanes
 *     for each product:
 *         4096 paired A coefficients
 *         4096 paired B coefficients
 *     TLAST only on the final B coefficient of the final product
 *
 * Batch result frame:
 *
 *     4096 paired result coefficients per product
 *     TLAST only on the final coefficient of the final product
 *
 * The input and output DMA channels remain one transaction each. MM2S
 * naturally stalls while the arithmetic core computes and while S2MM drains
 * each product. This checkpoint amortizes host/DMA transaction setup without
 * adding operand prefetch or result buffering.
 */
module poly_mul4096_four_butterfly_two_tower_batch_axis_core (
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

    output logic [31:0] completed_profiles,
    output logic [31:0] completed_products,
    output logic [31:0] completed_batches,

    output logic [31:0] active_batch_size,
    output logic [31:0] products_remaining,

    output logic [31:0] core_cycles_lane0,
    output logic [31:0] core_cycles_lane1,

    output logic [16:0] multiplication_count_lane0,
    output logic [16:0] multiplication_count_lane1
);

    localparam logic [31:0] COMMAND_PROFILE = 32'h50524f46;
    localparam logic [31:0] COMMAND_PRODUCT = 32'h4d554c31;
    localparam logic [31:0] COMMAND_BATCH   = 32'h4d554c42;

    localparam logic [13:0] LAST_PROFILE_INDEX = 14'd16381;
    localparam logic [13:0] PROFILE_FORWARD_BASE = 14'd4096;
    localparam logic [13:0] PROFILE_INVERSE_BASE = 14'd8191;
    localparam logic [13:0] PROFILE_SCALE_BASE = 14'd12286;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PROFILE_MODULUS,
        STATE_PROFILE_MU,
        STATE_PROFILE_PAYLOAD,
        STATE_PROFILE_COMMIT,
        STATE_BATCH_COUNT,
        STATE_PRODUCT_A,
        STATE_PRODUCT_B,
        STATE_PRODUCT_START,
        STATE_WAIT_CORE,
        STATE_OUTPUT_ISSUE,
        STATE_OUTPUT_SEND,
        STATE_DISCARD
    } state_t;

    state_t state;

    logic [63:0] captured_modulus;
    logic [13:0] profile_index;
    logic [11:0] coefficient_index;
    logic [11:0] output_index;
    logic batch_mode;

    wire input_handshake = s_axis_tvalid && s_axis_tready;
    wire output_handshake = m_axis_tvalid && m_axis_tready;

    wire profile_command =
        s_axis_tdata == {COMMAND_PROFILE, COMMAND_PROFILE};

    wire product_command =
        s_axis_tdata == {COMMAND_PRODUCT, COMMAND_PRODUCT};

    wire batch_command =
        s_axis_tdata == {COMMAND_BATCH, COMMAND_BATCH};

    wire final_input_coefficient =
        state == STATE_PRODUCT_B
        && coefficient_index == 12'd4095
        && products_remaining == 32'd1;

    wire final_output_coefficient =
        state == STATE_OUTPUT_SEND
        && output_index == 12'd4095
        && products_remaining == 32'd1;

    logic core_start;
    logic core_busy;
    logic core_done;

    logic core_load_a_we;
    logic [11:0] core_load_a_addr;
    logic [63:0] core_load_a_data;

    logic core_load_b_we;
    logic [11:0] core_load_b_addr;
    logic [63:0] core_load_b_data;

    logic core_profile_modulus_we;
    logic [63:0] core_profile_modulus_data;
    logic [61:0] core_profile_modulus_mu_data;

    logic core_profile_we;
    logic [1:0] core_profile_bank;
    logic [11:0] core_profile_addr;
    logic [63:0] core_profile_data;
    logic core_profile_commit;

    logic [63:0] core_read_a_data;
    logic [63:0] unused_core_read_b_data;

    assign core_start =
        state == STATE_PRODUCT_START;

    assign core_load_a_we =
        input_handshake
        && state == STATE_PRODUCT_A;

    assign core_load_a_addr =
        coefficient_index;

    assign core_load_a_data =
        s_axis_tdata;

    assign core_load_b_we =
        input_handshake
        && state == STATE_PRODUCT_B;

    assign core_load_b_addr =
        coefficient_index;

    assign core_load_b_data =
        s_axis_tdata;

    assign core_profile_modulus_we =
        input_handshake
        && state == STATE_PROFILE_MU;

    assign core_profile_modulus_data =
        captured_modulus;

    assign core_profile_modulus_mu_data = {
        s_axis_tdata[62:32],
        s_axis_tdata[30:0]
    };

    assign core_profile_we =
        input_handshake
        && state == STATE_PROFILE_PAYLOAD;

    assign core_profile_data =
        s_axis_tdata;

    assign core_profile_commit =
        state == STATE_PROFILE_COMMIT;

    always_comb
    begin
        core_profile_bank = 2'd0;
        core_profile_addr = 12'd0;

        if (profile_index < PROFILE_FORWARD_BASE)
        begin
            core_profile_bank = 2'd0;
            core_profile_addr = profile_index[11:0];
        end
        else if (profile_index < PROFILE_INVERSE_BASE)
        begin
            core_profile_bank = 2'd1;
            core_profile_addr =
                profile_index - PROFILE_FORWARD_BASE;
        end
        else if (profile_index < PROFILE_SCALE_BASE)
        begin
            core_profile_bank = 2'd2;
            core_profile_addr =
                profile_index - PROFILE_INVERSE_BASE;
        end
        else
        begin
            core_profile_bank = 2'd3;
            core_profile_addr =
                profile_index - PROFILE_SCALE_BASE;
        end
    end

    always_comb
    begin
        s_axis_tready = 1'b0;

        case (state)
            STATE_IDLE,
            STATE_PROFILE_MODULUS,
            STATE_PROFILE_MU,
            STATE_PROFILE_PAYLOAD,
            STATE_BATCH_COUNT,
            STATE_PRODUCT_A,
            STATE_PRODUCT_B,
            STATE_DISCARD:
            begin
                s_axis_tready = 1'b1;
            end

            default:
            begin
            end
        endcase
    end

    assign m_axis_tdata =
        core_read_a_data;

    assign m_axis_tvalid =
        state == STATE_OUTPUT_SEND;

    assign m_axis_tlast =
        final_output_coefficient;

    assign accelerator_busy =
        state != STATE_IDLE
        || core_busy;

    poly_mul4096_four_butterfly_two_tower_core core (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (core_start),

        .load_a_we                 (core_load_a_we),
        .load_a_addr               (core_load_a_addr),
        .load_a_data               (core_load_a_data),

        .load_b_we                 (core_load_b_we),
        .load_b_addr               (core_load_b_addr),
        .load_b_data               (core_load_b_data),

        .read_a_addr               (output_index),
        .read_a_data               (core_read_a_data),

        .read_b_addr               (12'd0),
        .read_b_data               (unused_core_read_b_data),

        .profile_modulus_we        (core_profile_modulus_we),
        .profile_modulus_data      (core_profile_modulus_data),
        .profile_modulus_mu_data   (
            core_profile_modulus_mu_data
        ),

        .profile_we                (core_profile_we),
        .profile_bank              (core_profile_bank),
        .profile_addr              (core_profile_addr),
        .profile_data              (core_profile_data),

        .profile_commit            (core_profile_commit),

        .profile_ready             (profile_ready),
        .active_modulus            (active_modulus),
        .active_modulus_mu         (active_modulus_mu),

        .busy                      (core_busy),
        .done                      (core_done),

        .cycles_lane0              (core_cycles_lane0),
        .cycles_lane1              (core_cycles_lane1),

        .multiplication_count_lane0(
            multiplication_count_lane0
        ),

        .multiplication_count_lane1(
            multiplication_count_lane1
        )
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;
            captured_modulus <= 64'd0;
            profile_index <= 14'd0;
            coefficient_index <= 12'd0;
            output_index <= 12'd0;
            batch_mode <= 1'b0;

            protocol_error <= 1'b0;
            completed_profiles <= 32'd0;
            completed_products <= 32'd0;
            completed_batches <= 32'd0;
            active_batch_size <= 32'd0;
            products_remaining <= 32'd0;
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
                            protocol_error <= 1'b1;
                        end
                        else if (profile_command)
                        begin
                            state <= STATE_PROFILE_MODULUS;
                        end
                        else if (
                            product_command
                            && profile_ready
                        )
                        begin
                            batch_mode <= 1'b0;
                            active_batch_size <= 32'd1;
                            products_remaining <= 32'd1;
                            coefficient_index <= 12'd0;
                            state <= STATE_PRODUCT_A;
                        end
                        else if (
                            batch_command
                            && profile_ready
                        )
                        begin
                            batch_mode <= 1'b1;
                            state <= STATE_BATCH_COUNT;
                        end
                        else
                        begin
                            protocol_error <= 1'b1;
                            state <= STATE_DISCARD;
                        end
                    end
                end

                STATE_PROFILE_MODULUS:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else
                        begin
                            captured_modulus <= s_axis_tdata;
                            state <= STATE_PROFILE_MU;
                        end
                    end
                end

                STATE_PROFILE_MU:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            || s_axis_tdata[63]
                            || s_axis_tdata[31]
                        )
                        begin
                            protocol_error <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else
                        begin
                            profile_index <= 14'd0;
                            state <= STATE_PROFILE_PAYLOAD;
                        end
                    end
                end

                STATE_PROFILE_PAYLOAD:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            != (
                                profile_index
                                == LAST_PROFILE_INDEX
                            )
                        )
                        begin
                            protocol_error <= 1'b1;
                            state <=
                                s_axis_tlast
                                    ? STATE_IDLE
                                    : STATE_DISCARD;
                        end
                        else if (
                            profile_index
                            == LAST_PROFILE_INDEX
                        )
                        begin
                            state <= STATE_PROFILE_COMMIT;
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

                    state <= STATE_IDLE;
                end

                STATE_BATCH_COUNT:
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
                            protocol_error <= 1'b1;
                            state <=
                                s_axis_tlast
                                    ? STATE_IDLE
                                    : STATE_DISCARD;
                        end
                        else
                        begin
                            active_batch_size <=
                                s_axis_tdata[31:0];

                            products_remaining <=
                                s_axis_tdata[31:0];

                            coefficient_index <= 12'd0;
                            state <= STATE_PRODUCT_A;
                        end
                    end
                end

                STATE_PRODUCT_A:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else if (
                            coefficient_index == 12'd4095
                        )
                        begin
                            coefficient_index <= 12'd0;
                            state <= STATE_PRODUCT_B;
                        end
                        else
                        begin
                            coefficient_index <=
                                coefficient_index + 1'b1;
                        end
                    end
                end

                STATE_PRODUCT_B:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            != final_input_coefficient
                        )
                        begin
                            protocol_error <= 1'b1;
                            state <=
                                s_axis_tlast
                                    ? STATE_IDLE
                                    : STATE_DISCARD;
                        end
                        else if (
                            coefficient_index == 12'd4095
                        )
                        begin
                            state <= STATE_PRODUCT_START;
                        end
                        else
                        begin
                            coefficient_index <=
                                coefficient_index + 1'b1;
                        end
                    end
                end

                STATE_PRODUCT_START:
                begin
                    state <= STATE_WAIT_CORE;
                end

                STATE_WAIT_CORE:
                begin
                    if (core_done)
                    begin
                        output_index <= 12'd0;
                        state <= STATE_OUTPUT_ISSUE;
                    end
                end

                STATE_OUTPUT_ISSUE:
                begin
                    state <= STATE_OUTPUT_SEND;
                end

                STATE_OUTPUT_SEND:
                begin
                    if (output_handshake)
                    begin
                        if (output_index == 12'd4095)
                        begin
                            completed_products <=
                                completed_products + 1'b1;

                            if (products_remaining == 32'd1)
                            begin
                                products_remaining <= 32'd0;

                                if (batch_mode)
                                begin
                                    completed_batches <=
                                        completed_batches + 1'b1;
                                end

                                state <= STATE_IDLE;
                            end
                            else
                            begin
                                products_remaining <=
                                    products_remaining - 1'b1;

                                coefficient_index <= 12'd0;
                                output_index <= 12'd0;
                                state <= STATE_PRODUCT_A;
                            end
                        end
                        else
                        begin
                            output_index <= output_index + 1'b1;
                            state <= STATE_OUTPUT_ISSUE;
                        end
                    end
                end

                STATE_DISCARD:
                begin
                    if (
                        input_handshake
                        && s_axis_tlast
                    )
                    begin
                        state <= STATE_IDLE;
                    end
                end

                default:
                begin
                    protocol_error <= 1'b1;
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            reset_n
            && core_done
            && (
                core_cycles_lane0 != 32'd22968
                || core_cycles_lane1 != 32'd22968
            )
        )
        begin
            $display(
                "ERROR: batch AXI core observed unexpected arithmetic cycles lane0=%0d lane1=%0d",
                core_cycles_lane0,
                core_cycles_lane1
            );

            $fatal(1);
        end

        if (
            reset_n
            && state != STATE_IDLE
            && state != STATE_PROFILE_MODULUS
            && state != STATE_PROFILE_MU
            && state != STATE_PROFILE_PAYLOAD
            && state != STATE_PROFILE_COMMIT
            && state != STATE_BATCH_COUNT
            && products_remaining == 32'd0
        )
        begin
            $display(
                "ERROR: active product state with zero products remaining state=%0d",
                state
            );

            $fatal(1);
        end
    end

`endif

endmodule
