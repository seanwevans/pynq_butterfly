`timescale 1ns/1ps

/*
 * Direct 64-bit AXI4-Stream adapter for the proven lockstep two-tower,
 * four-butterfly N=4096 negacyclic multiplier.
 *
 * Stream word packing:
 *
 *     bits 31:0  = tower 0
 *     bits 63:32 = tower 1
 *
 * Profile frame:
 *
 *     word 0: repeated command 0x50524f46 ("PROF")
 *     word 1: paired moduli
 *     word 2: paired Barrett reciprocals floor(2^60 / q)
 *     words 3..16384:
 *         4096 twist factors
 *         4095 forward DIF twiddles
 *         4095 inverse DIT twiddles
 *         4096 inverse-scale factors
 *
 *     TLAST is required on word 16384.
 *
 * Product frame:
 *
 *     word 0: repeated command 0x4d554c31 ("MUL1")
 *     words 1..4096: paired A coefficients
 *     words 4097..8192: paired B coefficients
 *
 *     TLAST is required on word 8192.
 *
 * Result frame:
 *
 *     4096 paired result coefficients
 *     TLAST on coefficient 4095
 */
module poly_mul4096_four_butterfly_two_tower_axis_core (
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

    output logic [31:0] core_cycles_lane0,
    output logic [31:0] core_cycles_lane1,

    output logic [16:0] multiplication_count_lane0,
    output logic [16:0] multiplication_count_lane1
);

    localparam logic [31:0] COMMAND_PROFILE = 32'h50524f46;
    localparam logic [31:0] COMMAND_PRODUCT = 32'h4d554c31;

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

    wire input_handshake = s_axis_tvalid && s_axis_tready;
    wire output_handshake = m_axis_tvalid && m_axis_tready;

    wire profile_command =
        s_axis_tdata == {COMMAND_PROFILE, COMMAND_PROFILE};

    wire product_command =
        s_axis_tdata == {COMMAND_PRODUCT, COMMAND_PRODUCT};

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

    assign core_start = state == STATE_PRODUCT_START;

    assign core_load_a_we =
        input_handshake && state == STATE_PRODUCT_A;

    assign core_load_a_addr = coefficient_index;
    assign core_load_a_data = s_axis_tdata;

    assign core_load_b_we =
        input_handshake && state == STATE_PRODUCT_B;

    assign core_load_b_addr = coefficient_index;
    assign core_load_b_data = s_axis_tdata;

    /*
     * Modulus and reciprocal are committed together when the reciprocal
     * word arrives. Each 32-bit stream lane contains a zero-extended
     * 31-bit reciprocal.
     */
    assign core_profile_modulus_we =
        input_handshake && state == STATE_PROFILE_MU;

    assign core_profile_modulus_data = captured_modulus;

    assign core_profile_modulus_mu_data = {
        s_axis_tdata[62:32],
        s_axis_tdata[30:0]
    };

    assign core_profile_we =
        input_handshake && state == STATE_PROFILE_PAYLOAD;

    assign core_profile_data = s_axis_tdata;
    assign core_profile_commit = state == STATE_PROFILE_COMMIT;

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
            core_profile_addr = profile_index - PROFILE_FORWARD_BASE;
        end
        else if (profile_index < PROFILE_SCALE_BASE)
        begin
            core_profile_bank = 2'd2;
            core_profile_addr = profile_index - PROFILE_INVERSE_BASE;
        end
        else
        begin
            core_profile_bank = 2'd3;
            core_profile_addr = profile_index - PROFILE_SCALE_BASE;
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

    assign m_axis_tdata = core_read_a_data;
    assign m_axis_tvalid = state == STATE_OUTPUT_SEND;
    assign m_axis_tlast =
        state == STATE_OUTPUT_SEND && output_index == 12'd4095;

    assign accelerator_busy = state != STATE_IDLE || core_busy;

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
        .profile_modulus_mu_data   (core_profile_modulus_mu_data),

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

        .multiplication_count_lane0(multiplication_count_lane0),
        .multiplication_count_lane1(multiplication_count_lane1)
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
            protocol_error <= 1'b0;
            completed_profiles <= 32'd0;
            completed_products <= 32'd0;
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
                        else if (product_command && profile_ready)
                        begin
                            coefficient_index <= 12'd0;
                            state <= STATE_PRODUCT_A;
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
                        if (s_axis_tlast || s_axis_tdata[63] || s_axis_tdata[31])
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
                            s_axis_tlast !=
                            (profile_index == LAST_PROFILE_INDEX)
                        )
                        begin
                            protocol_error <= 1'b1;
                            state <= s_axis_tlast ? STATE_IDLE : STATE_DISCARD;
                        end
                        else if (profile_index == LAST_PROFILE_INDEX)
                        begin
                            state <= STATE_PROFILE_COMMIT;
                        end
                        else
                        begin
                            profile_index <= profile_index + 1'b1;
                        end
                    end
                end

                STATE_PROFILE_COMMIT:
                begin
                    completed_profiles <= completed_profiles + 1'b1;
                    state <= STATE_IDLE;
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
                        else if (coefficient_index == 12'd4095)
                        begin
                            coefficient_index <= 12'd0;
                            state <= STATE_PRODUCT_B;
                        end
                        else
                        begin
                            coefficient_index <= coefficient_index + 1'b1;
                        end
                    end
                end

                STATE_PRODUCT_B:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast !=
                            (coefficient_index == 12'd4095)
                        )
                        begin
                            protocol_error <= 1'b1;
                            state <= s_axis_tlast ? STATE_IDLE : STATE_DISCARD;
                        end
                        else if (coefficient_index == 12'd4095)
                        begin
                            state <= STATE_PRODUCT_START;
                        end
                        else
                        begin
                            coefficient_index <= coefficient_index + 1'b1;
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
                            completed_products <= completed_products + 1'b1;
                            state <= STATE_IDLE;
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
                    if (input_handshake && s_axis_tlast)
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
                "ERROR: AXI core observed unexpected cycles lane0=%0d lane1=%0d",
                core_cycles_lane0,
                core_cycles_lane1
            );
            $fatal(1);
        end
    end

`endif

endmodule
