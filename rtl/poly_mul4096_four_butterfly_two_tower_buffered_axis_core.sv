`timescale 1ns/1ps

/*
 * Batched 64-bit AXI4-Stream adapter with one-product operand prefetch,
 * eight-wide result/refill handoff, and one-product result buffering.
 *
 * Steady-state schedule:
 *
 *     receive product k+1 while core computes product k
 *     512 read issues + one synchronous drain hand off result k and refill k+1
 *     compute product k+1 while result k streams independently
 */
module poly_mul4096_four_butterfly_two_tower_buffered_axis_core (
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
    output logic [31:0] completed_prefetches,
    output logic [31:0] completed_refills,
    output logic [31:0] completed_handoffs,
    output logic [31:0] last_handoff_cycles,
    output logic        compute_output_overlap_observed,

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
        INPUT_IDLE,
        INPUT_PROFILE_MODULUS,
        INPUT_PROFILE_MU,
        INPUT_PROFILE_PAYLOAD,
        INPUT_PROFILE_COMMIT,
        INPUT_BATCH_COUNT,
        INPUT_DIRECT_A,
        INPUT_DIRECT_B,
        INPUT_SHADOW_A,
        INPUT_SHADOW_B,
        INPUT_WAIT_SHADOW_FREE,
        INPUT_WAIT_BATCH_COMPLETE,
        INPUT_DISCARD
    } input_state_t;

    typedef enum logic [2:0] {
        EXEC_IDLE,
        EXEC_START_FIRST,
        EXEC_WAIT_CORE,
        EXEC_WAIT_RESOURCES,
        EXEC_HANDOFF_ISSUE,
        EXEC_HANDOFF_DRAIN
    } exec_state_t;

    typedef enum logic [1:0] {
        OUTPUT_IDLE,
        OUTPUT_ISSUE,
        OUTPUT_SEND
    } output_state_t;

    input_state_t input_state;
    exec_state_t exec_state;
    output_state_t output_state;

    logic [63:0] captured_modulus;
    logic [13:0] profile_index;
    logic [11:0] input_coefficient_index;
    logic [11:0] output_index;
    logic [31:0] batch_count;
    logic [31:0] input_product_index;
    logic [31:0] exec_product_index;
    logic batch_mode;

    logic shadow_full;
    logic result_buffer_full;
    logic result_buffer_final;

    logic [8:0] handoff_issue_group;
    logic [8:0] handoff_data_group;
    logic [31:0] handoff_cycle_counter;
    logic handoff_final_latched;

    wire input_handshake =
        s_axis_tvalid
        && s_axis_tready;

    wire output_handshake =
        m_axis_tvalid
        && m_axis_tready;

    wire profile_command =
        s_axis_tdata == {COMMAND_PROFILE, COMMAND_PROFILE};

    wire product_command =
        s_axis_tdata == {COMMAND_PRODUCT, COMMAND_PRODUCT};

    wire batch_command =
        s_axis_tdata == {COMMAND_BATCH, COMMAND_BATCH};

    wire product_command_accepted =
        input_handshake
        && input_state == INPUT_IDLE
        && product_command
        && profile_ready;

    wire batch_count_accepted =
        input_handshake
        && input_state == INPUT_BATCH_COUNT
        && !s_axis_tlast
        && s_axis_tdata[31:0] != 32'd0
        && s_axis_tdata[63:32] == s_axis_tdata[31:0];

    wire final_input_product =
        input_product_index + 1'b1 == batch_count;

    wire direct_fill_done =
        input_handshake
        && input_state == INPUT_DIRECT_B
        && input_coefficient_index == 12'd4095;

    wire shadow_fill_done =
        input_handshake
        && input_state == INPUT_SHADOW_B
        && input_coefficient_index == 12'd4095;

    wire final_exec_product =
        exec_product_index + 1'b1 == batch_count;

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

    logic core_handoff_read_valid;
    logic [11:0] core_handoff_read_base;
    logic core_handoff_read_data_valid;
    logic [7:0][63:0] core_handoff_read_data;
    logic core_handoff_write_valid;
    logic [11:0] core_handoff_write_base;

    logic shadow_load_a_we;
    logic shadow_load_b_we;
    logic shadow_read_valid;
    logic [7:0][11:0] shadow_read_address;
    logic shadow_a_read_data_valid;
    logic shadow_b_read_data_valid;
    logic [7:0][63:0] shadow_a_read_data;
    logic [7:0][63:0] shadow_b_read_data;

    logic result_read_valid;
    logic [7:0][11:0] result_read_address;
    logic result_read_data_valid;
    logic [7:0][63:0] result_read_data;
    logic result_write_valid;
    logic [7:0][11:0] handoff_address;

    logic [63:0] unused_core_read_a_data;
    logic [63:0] unused_core_read_b_data;

    wire handoff_issue_valid =
        exec_state == EXEC_HANDOFF_ISSUE;

    wire handoff_commit_valid =
        core_handoff_read_data_valid
        && (
            handoff_final_latched
            || (
                shadow_a_read_data_valid
                && shadow_b_read_data_valid
            )
        );

    wire handoff_commit_last =
        handoff_commit_valid
        && handoff_data_group == 9'd511;

    wire shadow_consume =
        handoff_commit_last
        && !handoff_final_latched;

    wire result_buffer_consume =
        output_state == OUTPUT_SEND
        && output_handshake
        && output_index == 12'd4095;

    wire final_result_consumed =
        result_buffer_consume
        && result_buffer_final;

    wire handoff_resources_ready =
        !result_buffer_full
        && (
            final_exec_product
            || shadow_full
        );

    integer address_lane;

    always_comb
    begin
        for (
            address_lane = 0;
            address_lane < 8;
            address_lane = address_lane + 1
        )
        begin
            handoff_address[address_lane] =
                {
                    handoff_data_group,
                    3'b000
                }
                + address_lane[11:0];

            shadow_read_address[address_lane] =
                {
                    handoff_issue_group,
                    3'b000
                }
                + address_lane[11:0];

            result_read_address[address_lane] =
                output_index ^ address_lane[11:0];
        end
    end

    assign core_start =
        exec_state == EXEC_START_FIRST
        || (
            exec_state == EXEC_HANDOFF_DRAIN
            && handoff_commit_last
            && !handoff_final_latched
        );

    assign core_load_a_we =
        input_handshake
        && input_state == INPUT_DIRECT_A;

    assign core_load_a_addr =
        input_coefficient_index;

    assign core_load_a_data =
        s_axis_tdata;

    assign core_load_b_we =
        input_handshake
        && input_state == INPUT_DIRECT_B;

    assign core_load_b_addr =
        input_coefficient_index;

    assign core_load_b_data =
        s_axis_tdata;

    assign shadow_load_a_we =
        input_handshake
        && input_state == INPUT_SHADOW_A;

    assign shadow_load_b_we =
        input_handshake
        && input_state == INPUT_SHADOW_B;

    assign shadow_read_valid =
        handoff_issue_valid
        && !handoff_final_latched;

    assign core_handoff_read_valid =
        handoff_issue_valid;

    assign core_handoff_read_base = {
        handoff_issue_group,
        3'b000
    };

    assign core_handoff_write_valid =
        handoff_commit_valid
        && !handoff_final_latched;

    assign core_handoff_write_base = {
        handoff_data_group,
        3'b000
    };

    assign result_write_valid =
        handoff_commit_valid;

    assign result_read_valid =
        output_state == OUTPUT_ISSUE;

    assign core_profile_modulus_we =
        input_handshake
        && input_state == INPUT_PROFILE_MU;

    assign core_profile_modulus_data =
        captured_modulus;

    assign core_profile_modulus_mu_data = {
        s_axis_tdata[62:32],
        s_axis_tdata[30:0]
    };

    assign core_profile_we =
        input_handshake
        && input_state == INPUT_PROFILE_PAYLOAD;

    assign core_profile_data =
        s_axis_tdata;

    assign core_profile_commit =
        input_state == INPUT_PROFILE_COMMIT;

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

    always_comb
    begin
        s_axis_tready =
            1'b0;

        case (input_state)
            INPUT_IDLE,
            INPUT_PROFILE_MODULUS,
            INPUT_PROFILE_MU,
            INPUT_PROFILE_PAYLOAD,
            INPUT_BATCH_COUNT,
            INPUT_DIRECT_A,
            INPUT_DIRECT_B,
            INPUT_SHADOW_A,
            INPUT_SHADOW_B,
            INPUT_DISCARD:
            begin
                s_axis_tready =
                    1'b1;
            end

            default:
            begin
            end
        endcase
    end

    assign m_axis_tdata =
        result_read_data[0];

    assign m_axis_tvalid =
        output_state == OUTPUT_SEND;

    assign m_axis_tlast =
        m_axis_tvalid
        && output_index == 12'd4095
        && result_buffer_final;

    assign accelerator_busy =
        input_state != INPUT_IDLE
        || exec_state != EXEC_IDLE
        || output_state != OUTPUT_IDLE
        || core_busy
        || shadow_full
        || result_buffer_full;

    ntt4096_eight_bank_coeff_store_runtime64 shadow_store_a (
        .clk             (clk),
        .load_we         (shadow_load_a_we),
        .load_addr       (input_coefficient_index),
        .load_data       (s_axis_tdata),
        .read_valid      (shadow_read_valid),
        .read_addr       (shadow_read_address),
        .read_data_valid (shadow_a_read_data_valid),
        .read_data       (shadow_a_read_data),
        .write_valid     (1'b0),
        .write_addr      ('0),
        .write_data      ('0)
    );

    ntt4096_eight_bank_coeff_store_runtime64 shadow_store_b (
        .clk             (clk),
        .load_we         (shadow_load_b_we),
        .load_addr       (input_coefficient_index),
        .load_data       (s_axis_tdata),
        .read_valid      (shadow_read_valid),
        .read_addr       (shadow_read_address),
        .read_data_valid (shadow_b_read_data_valid),
        .read_data       (shadow_b_read_data),
        .write_valid     (1'b0),
        .write_addr      ('0),
        .write_data      ('0)
    );

    ntt4096_eight_bank_coeff_store_runtime64 result_store (
        .clk             (clk),
        .load_we         (1'b0),
        .load_addr       (12'd0),
        .load_data       (64'd0),
        .read_valid      (result_read_valid),
        .read_addr       (result_read_address),
        .read_data_valid (result_read_data_valid),
        .read_data       (result_read_data),
        .write_valid     (result_write_valid),
        .write_addr      (handoff_address),
        .write_data      (core_handoff_read_data)
    );

    poly_mul4096_four_butterfly_two_tower_handoff_core core (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (core_start),
        .load_a_we                 (core_load_a_we),
        .load_a_addr               (core_load_a_addr),
        .load_a_data               (core_load_a_data),
        .load_b_we                 (core_load_b_we),
        .load_b_addr               (core_load_b_addr),
        .load_b_data               (core_load_b_data),
        .read_a_addr               (12'd0),
        .read_a_data               (unused_core_read_a_data),
        .read_b_addr               (12'd0),
        .read_b_data               (unused_core_read_b_data),
        .handoff_read_valid        (core_handoff_read_valid),
        .handoff_read_base         (core_handoff_read_base),
        .handoff_read_data_valid   (core_handoff_read_data_valid),
        .handoff_read_data         (core_handoff_read_data),
        .handoff_write_valid       (core_handoff_write_valid),
        .handoff_write_base        (core_handoff_write_base),
        .handoff_write_a_data      (shadow_a_read_data),
        .handoff_write_b_data      (shadow_b_read_data),
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
            shadow_full <=
                1'b0;
        end
        else
        begin
            case ({shadow_fill_done, shadow_consume})
                2'b10:
                begin
                    shadow_full <=
                        1'b1;
                end

                2'b01:
                begin
                    shadow_full <=
                        1'b0;
                end

                2'b11:
                begin
                    shadow_full <=
                        1'b1;
                end

                default:
                begin
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            result_buffer_full <=
                1'b0;

            result_buffer_final <=
                1'b0;
        end
        else
        begin
            case ({handoff_commit_last, result_buffer_consume})
                2'b10,
                2'b11:
                begin
                    result_buffer_full <=
                        1'b1;

                    result_buffer_final <=
                        handoff_final_latched;
                end

                2'b01:
                begin
                    result_buffer_full <=
                        1'b0;

                    result_buffer_final <=
                        1'b0;
                end

                default:
                begin
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            input_state <=
                INPUT_IDLE;

            captured_modulus <=
                64'd0;

            profile_index <=
                14'd0;

            input_coefficient_index <=
                12'd0;

            batch_count <=
                32'd1;

            input_product_index <=
                32'd0;

            batch_mode <=
                1'b0;

            protocol_error <=
                1'b0;

            completed_profiles <=
                32'd0;

            completed_prefetches <=
                32'd0;

            active_batch_size <=
                32'd0;
        end
        else
        begin
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
                                INPUT_PROFILE_MODULUS;
                        end
                        else if (product_command && profile_ready)
                        begin
                            batch_mode <=
                                1'b0;

                            batch_count <=
                                32'd1;

                            active_batch_size <=
                                32'd1;

                            input_product_index <=
                                32'd0;

                            input_coefficient_index <=
                                12'd0;

                            input_state <=
                                INPUT_DIRECT_A;
                        end
                        else if (batch_command && profile_ready)
                        begin
                            batch_mode <=
                                1'b1;

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

                INPUT_PROFILE_MODULUS:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_IDLE;
                        end
                        else
                        begin
                            captured_modulus <=
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
                            s_axis_tlast
                            || s_axis_tdata[63]
                            || s_axis_tdata[31]
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_IDLE;
                        end
                        else
                        begin
                            profile_index <=
                                14'd0;

                            input_state <=
                                INPUT_PROFILE_PAYLOAD;
                        end
                    end
                end

                INPUT_PROFILE_PAYLOAD:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            != (profile_index == LAST_PROFILE_INDEX)
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                s_axis_tlast
                                    ? INPUT_IDLE
                                    : INPUT_DISCARD;
                        end
                        else if (profile_index == LAST_PROFILE_INDEX)
                        begin
                            input_state <=
                                INPUT_PROFILE_COMMIT;
                        end
                        else
                        begin
                            profile_index <=
                                profile_index + 1'b1;
                        end
                    end
                end

                INPUT_PROFILE_COMMIT:
                begin
                    completed_profiles <=
                        completed_profiles + 1'b1;

                    input_state <=
                        INPUT_IDLE;
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

                            input_product_index <=
                                32'd0;

                            input_coefficient_index <=
                                12'd0;

                            input_state <=
                                INPUT_DIRECT_A;
                        end
                    end
                end

                INPUT_DIRECT_A,
                INPUT_SHADOW_A:
                begin
                    if (input_handshake)
                    begin
                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_IDLE;
                        end
                        else if (input_coefficient_index == 12'd4095)
                        begin
                            input_coefficient_index <=
                                12'd0;

                            input_state <=
                                input_state == INPUT_DIRECT_A
                                    ? INPUT_DIRECT_B
                                    : INPUT_SHADOW_B;
                        end
                        else
                        begin
                            input_coefficient_index <=
                                input_coefficient_index + 1'b1;
                        end
                    end
                end

                INPUT_DIRECT_B,
                INPUT_SHADOW_B:
                begin
                    if (input_handshake)
                    begin
                        if (
                            s_axis_tlast
                            != (
                                input_coefficient_index == 12'd4095
                                && final_input_product
                            )
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                s_axis_tlast
                                    ? INPUT_IDLE
                                    : INPUT_DISCARD;
                        end
                        else if (input_coefficient_index == 12'd4095)
                        begin
                            input_product_index <=
                                input_product_index + 1'b1;

                            input_coefficient_index <=
                                12'd0;

                            if (final_input_product)
                            begin
                                input_state <=
                                    INPUT_WAIT_BATCH_COMPLETE;
                            end
                            else if (input_state == INPUT_DIRECT_B)
                            begin
                                input_state <=
                                    INPUT_SHADOW_A;
                            end
                            else
                            begin
                                input_state <=
                                    INPUT_WAIT_SHADOW_FREE;
                            end
                        end
                        else
                        begin
                            input_coefficient_index <=
                                input_coefficient_index + 1'b1;
                        end
                    end
                end

                INPUT_WAIT_SHADOW_FREE:
                begin
                    if (!shadow_full)
                    begin
                        input_state <=
                            INPUT_SHADOW_A;
                    end
                end

                INPUT_WAIT_BATCH_COMPLETE:
                begin
                    if (final_result_consumed)
                    begin
                        input_state <=
                            INPUT_IDLE;
                    end
                end

                INPUT_DISCARD:
                begin
                    if (input_handshake && s_axis_tlast)
                    begin
                        input_state <=
                            INPUT_IDLE;
                    end
                end

                default:
                begin
                    protocol_error <=
                        1'b1;

                    input_state <=
                        INPUT_IDLE;
                end
            endcase

            if (shadow_fill_done)
            begin
                completed_prefetches <=
                    completed_prefetches + 1'b1;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            exec_state <=
                EXEC_IDLE;

            exec_product_index <=
                32'd0;

            handoff_issue_group <=
                9'd0;

            handoff_data_group <=
                9'd0;

            handoff_cycle_counter <=
                32'd0;

            handoff_final_latched <=
                1'b0;

            completed_refills <=
                32'd0;

            completed_handoffs <=
                32'd0;

            last_handoff_cycles <=
                32'd0;

            compute_output_overlap_observed <=
                1'b0;
        end
        else
        begin
            if (core_busy && output_state != OUTPUT_IDLE)
            begin
                compute_output_overlap_observed <=
                    1'b1;
            end

            case (exec_state)
                EXEC_IDLE:
                begin
                    if (direct_fill_done)
                    begin
                        exec_product_index <=
                            32'd0;

                        exec_state <=
                            EXEC_START_FIRST;
                    end
                end

                EXEC_START_FIRST:
                begin
                    exec_state <=
                        EXEC_WAIT_CORE;
                end

                EXEC_WAIT_CORE:
                begin
                    if (core_done)
                    begin
                        handoff_final_latched <=
                            final_exec_product;

                        handoff_issue_group <=
                            9'd0;

                        handoff_cycle_counter <=
                            32'd0;

                        exec_state <=
                            handoff_resources_ready
                                ? EXEC_HANDOFF_ISSUE
                                : EXEC_WAIT_RESOURCES;
                    end
                end

                EXEC_WAIT_RESOURCES:
                begin
                    if (handoff_resources_ready)
                    begin
                        handoff_issue_group <=
                            9'd0;

                        handoff_cycle_counter <=
                            32'd0;

                        exec_state <=
                            EXEC_HANDOFF_ISSUE;
                    end
                end

                EXEC_HANDOFF_ISSUE:
                begin
                    handoff_data_group <=
                        handoff_issue_group;

                    handoff_cycle_counter <=
                        handoff_cycle_counter + 1'b1;

                    if (handoff_issue_group == 9'd511)
                    begin
                        exec_state <=
                            EXEC_HANDOFF_DRAIN;
                    end
                    else
                    begin
                        handoff_issue_group <=
                            handoff_issue_group + 1'b1;
                    end
                end

                EXEC_HANDOFF_DRAIN:
                begin
                    handoff_cycle_counter <=
                        handoff_cycle_counter + 1'b1;

                    if (handoff_commit_last)
                    begin
                        completed_handoffs <=
                            completed_handoffs + 1'b1;

                        last_handoff_cycles <=
                            handoff_cycle_counter + 1'b1;

                        if (handoff_final_latched)
                        begin
                            exec_state <=
                                EXEC_IDLE;
                        end
                        else
                        begin
                            completed_refills <=
                                completed_refills + 1'b1;

                            exec_product_index <=
                                exec_product_index + 1'b1;

                            exec_state <=
                                EXEC_WAIT_CORE;
                        end
                    end
                end

                default:
                begin
                    exec_state <=
                        EXEC_IDLE;
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            output_state <=
                OUTPUT_IDLE;

            output_index <=
                12'd0;

            completed_products <=
                32'd0;

            completed_batches <=
                32'd0;

            products_remaining <=
                32'd0;
        end
        else
        begin
            if (product_command_accepted)
            begin
                products_remaining <=
                    32'd1;
            end
            else if (batch_count_accepted)
            begin
                products_remaining <=
                    s_axis_tdata[31:0];
            end
            else if (result_buffer_consume)
            begin
                products_remaining <=
                    products_remaining - 1'b1;
            end

            case (output_state)
                OUTPUT_IDLE:
                begin
                    if (result_buffer_full)
                    begin
                        output_index <=
                            12'd0;

                        output_state <=
                            OUTPUT_ISSUE;
                    end
                end

                OUTPUT_ISSUE:
                begin
                    output_state <=
                        OUTPUT_SEND;
                end

                OUTPUT_SEND:
                begin
                    if (output_handshake)
                    begin
                        if (output_index == 12'd4095)
                        begin
                            completed_products <=
                                completed_products + 1'b1;

                            if (result_buffer_final && batch_mode)
                            begin
                                completed_batches <=
                                    completed_batches + 1'b1;
                            end

                            output_state <=
                                OUTPUT_IDLE;
                        end
                        else
                        begin
                            output_index <=
                                output_index + 1'b1;

                            output_state <=
                                OUTPUT_ISSUE;
                        end
                    end
                end

                default:
                begin
                    output_state <=
                        OUTPUT_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (reset_n)
        begin
            if (core_handoff_write_valid && !shadow_full)
            begin
                $display("ERROR: refill attempted without prefetched product");
                $fatal(1);
            end

            if (result_write_valid && result_buffer_full)
            begin
                $display("ERROR: result handoff overwrote a full result buffer");
                $fatal(1);
            end

            if (last_handoff_cycles != 0 && last_handoff_cycles != 32'd513)
            begin
                $display(
                    "ERROR: eight-wide handoff took %0d clocks, expected 513",
                    last_handoff_cycles
                );
                $fatal(1);
            end
        end
    end

`endif

endmodule
