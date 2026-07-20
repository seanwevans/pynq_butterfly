`timescale 1ns/1ps

/*
 * Runtime-profile AXI4-Stream adapter with one-product operand prefetch
 * and one-product result buffering.
 *
 * Product zero is loaded directly into the unchanged arithmetic stores.
 * While product k computes, product k+1 is accepted into two four-bank
 * shadow stores.  After product k completes, four result coefficients per clock are
 * copied into a dedicated result store while four shadow A/B
 * coefficients refill the arithmetic stores.  Product k+1 then starts
 * while result k streams independently to AXI.
 *
 * The handoff uses the independent read/write ports of all four banks.
 * The result store decouples the 1024-group handoff from scalar AXI
 * output and permits computation/output overlap.
 *
 * The arithmetic FSM, modular multipliers, profile memories, and exact
 * 631810-cycle hardware schedule are unchanged.  The only arithmetic-
 * core source change keeps the idle A read port enabled during an
 * external load; the underlying coefficient RAMs already have separate
 * synchronous read and write ports.
 */
module poly_mul4096_dual_butterfly_runtime_profile_buffered_axis_core (
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
    output logic [31:0] completed_batches,
    output logic [31:0] completed_prefetches,
    output logic [31:0] completed_refills,
    output logic [31:0] completed_handoffs,
    output logic [31:0] last_handoff_cycles,
    output logic        compute_output_overlap_observed,

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

    localparam logic [31:0] COMMAND_BATCH =
        32'h4d554c42;

    localparam integer PROFILE_PAYLOAD_WORDS =
        16382;

    localparam integer PROFILE_FORWARD_BASE =
        4096;

    localparam integer PROFILE_INVERSE_BASE =
        8191;

    localparam integer PROFILE_SCALE_BASE =
        12286;

    typedef enum logic [3:0] {
        INPUT_IDLE,
        INPUT_PROFILE_MODULUS,
        INPUT_PROFILE_PAYLOAD,
        INPUT_PROFILE_COMMIT,
        INPUT_BATCH_COUNT,
        INPUT_DIRECT_A,
        INPUT_DIRECT_B,
        INPUT_DIRECT_DRAIN,
        INPUT_SHADOW_A,
        INPUT_SHADOW_B,
        INPUT_SHADOW_DRAIN,
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

    input_state_t  input_state;
    exec_state_t   exec_state;
    output_state_t output_state;

    logic [13:0] profile_index;
    logic [11:0] input_coefficient_index;
    logic [11:0] output_index;

    logic [9:0]  handoff_issue_group;
    logic [9:0]  handoff_data_group;
    logic [31:0] handoff_cycle_counter;
    logic        handoff_final_latched;

    logic        batch_mode;
    logic [31:0] batch_count;
    logic [31:0] input_product_index;
    logic [31:0] exec_product_index;

    logic input_handshake;
    logic output_handshake;

    logic final_input_product;
    logic final_exec_product;

    logic shadow_full;
    logic shadow_fill_done;
    logic shadow_consume;
    logic batch_complete;

    logic result_buffer_full;
    logic result_buffer_final;
    logic result_buffer_fill_done;
    logic result_buffer_consume;

    logic handoff_resources_ready;
    logic handoff_issue_valid;
    logic handoff_commit_valid;
    logic handoff_commit_last;

    logic core_start;
    logic core_busy;
    logic core_done;

    logic core_load_a_we;
    logic [11:0] core_load_a_addr;
    logic [31:0] core_load_a_data;

    logic core_load_b_we;
    logic [11:0] core_load_b_addr;
    logic [31:0] core_load_b_data;

    logic core_load_a_we_reg;
    logic [11:0] core_load_a_addr_reg;
    logic [31:0] core_load_a_data_reg;

    logic core_load_b_we_reg;
    logic [11:0] core_load_b_addr_reg;
    logic [31:0] core_load_b_data_reg;

    logic [31:0] unused_core_read_a_data;
    logic [31:0] unused_core_read_b_data;

    logic        core_handoff_read_valid;
    logic [11:0] core_handoff_read_base;
    logic        core_handoff_read_data_valid;
    logic [31:0] core_handoff_read_data0;
    logic [31:0] core_handoff_read_data1;
    logic [31:0] core_handoff_read_data2;
    logic [31:0] core_handoff_read_data3;

    logic        core_handoff_write_valid;
    logic [11:0] core_handoff_write_base;

    logic shadow_load_a_we_reg;
    logic [11:0] shadow_load_a_addr_reg;
    logic [31:0] shadow_load_a_data_reg;

    logic shadow_load_b_we_reg;
    logic [11:0] shadow_load_b_addr_reg;
    logic [31:0] shadow_load_b_data_reg;

    logic shadow_read_valid;
    logic [11:0] shadow_read_addr0;
    logic [11:0] shadow_read_addr1;
    logic [11:0] shadow_read_addr2;
    logic [11:0] shadow_read_addr3;

    logic shadow_a_read_data_valid;
    logic [31:0] shadow_a_read_data0;
    logic [31:0] shadow_a_read_data1;
    logic [31:0] shadow_a_read_data2;
    logic [31:0] shadow_a_read_data3;

    logic shadow_b_read_data_valid;
    logic [31:0] shadow_b_read_data0;
    logic [31:0] shadow_b_read_data1;
    logic [31:0] shadow_b_read_data2;
    logic [31:0] shadow_b_read_data3;

    logic result_read_valid;
    logic [11:0] result_read_addr0;
    logic [11:0] result_read_addr1;
    logic [11:0] result_read_addr2;
    logic [11:0] result_read_addr3;
    logic result_read_data_valid;
    logic [31:0] result_read_data0;
    logic [31:0] unused_result_read_data1;
    logic [31:0] unused_result_read_data2;
    logic [31:0] unused_result_read_data3;

    logic core_profile_modulus_we;
    logic [31:0] core_profile_modulus_data;

    logic core_profile_we;
    logic [1:0] core_profile_bank;
    logic [11:0] core_profile_addr;
    logic [31:0] core_profile_data;
    logic core_profile_commit;

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

    assign final_input_product =
        input_product_index + 1'b1 == batch_count;

    assign final_exec_product =
        exec_product_index + 1'b1 == batch_count;

    assign shadow_fill_done =
        input_state == INPUT_SHADOW_DRAIN;

    assign handoff_resources_ready =
        !result_buffer_full
        && (final_exec_product || shadow_full);

    assign handoff_issue_valid =
        exec_state == EXEC_HANDOFF_ISSUE;

    assign core_handoff_read_valid =
        handoff_issue_valid;

    assign core_handoff_read_base = {
        handoff_issue_group,
        2'b00
    };

    assign handoff_commit_valid =
        core_handoff_read_data_valid
        && (
            handoff_final_latched
            || (
                shadow_a_read_data_valid
                && shadow_b_read_data_valid
            )
        );

    assign handoff_commit_last =
        handoff_commit_valid
        && handoff_data_group == 10'd1023;

    assign shadow_consume =
        handoff_commit_last
        && !handoff_final_latched;

    assign result_buffer_fill_done =
        handoff_commit_last;

    assign result_buffer_consume =
        output_state == OUTPUT_SEND
        && output_handshake
        && output_index == 12'd4095;

    assign batch_complete =
        result_buffer_consume
        && result_buffer_final;

    assign accelerator_busy =
        core_busy
        || input_state != INPUT_IDLE
        || exec_state != EXEC_IDLE
        || output_state != OUTPUT_IDLE
        || shadow_full
        || result_buffer_full;

    always_comb
    begin
        s_axis_tready =
            1'b0;

        case (input_state)
            INPUT_IDLE,
            INPUT_PROFILE_MODULUS,
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

    assign core_start =
        exec_state == EXEC_START_FIRST
        || (
            exec_state == EXEC_HANDOFF_DRAIN
            && handoff_commit_last
            && !handoff_final_latched
        );

    assign core_profile_commit =
        input_state == INPUT_PROFILE_COMMIT;

    assign core_profile_modulus_we =
        input_handshake
        && input_state == INPUT_PROFILE_MODULUS;

    assign core_profile_modulus_data =
        s_axis_tdata;

    assign core_profile_we =
        input_handshake
        && input_state == INPUT_PROFILE_PAYLOAD;

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
        core_load_a_we_reg;

    assign core_load_a_addr =
        core_load_a_addr_reg;

    assign core_load_a_data =
        core_load_a_data_reg;

    assign core_load_b_we =
        core_load_b_we_reg;

    assign core_load_b_addr =
        core_load_b_addr_reg;

    assign core_load_b_data =
        core_load_b_data_reg;

    assign m_axis_tdata =
        result_read_data0;

    assign m_axis_tvalid =
        output_state == OUTPUT_SEND;

    assign m_axis_tlast =
        output_state == OUTPUT_SEND
        && output_index == 12'd4095
        && result_buffer_final;

    assign shadow_read_valid =
        handoff_issue_valid
        && !handoff_final_latched;

    assign shadow_read_addr0 =
        core_handoff_read_base;

    assign shadow_read_addr1 =
        core_handoff_read_base + 12'd1;

    assign shadow_read_addr2 =
        core_handoff_read_base + 12'd2;

    assign shadow_read_addr3 =
        core_handoff_read_base + 12'd3;

    assign core_handoff_write_valid =
        handoff_commit_valid
        && !handoff_final_latched;

    assign core_handoff_write_base = {
        handoff_data_group,
        2'b00
    };

    assign result_read_valid =
        output_state == OUTPUT_ISSUE;

    assign result_read_addr0 =
        output_index;

    assign result_read_addr1 = {
        output_index[11:2],
        output_index[1:0] + 2'd1
    };

    assign result_read_addr2 = {
        output_index[11:2],
        output_index[1:0] + 2'd2
    };

    assign result_read_addr3 = {
        output_index[11:2],
        output_index[1:0] + 2'd3
    };

    /*
     * Registered scalar write boundaries preserve the timing isolation
     * already proven by the batch overlay. Four-wide handoff writes use
     * the separate idle-only port on the arithmetic core.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            core_load_a_we_reg <=
                1'b0;

            core_load_a_addr_reg <=
                12'd0;

            core_load_a_data_reg <=
                32'd0;

            core_load_b_we_reg <=
                1'b0;

            core_load_b_addr_reg <=
                12'd0;

            core_load_b_data_reg <=
                32'd0;

            shadow_load_a_we_reg <=
                1'b0;

            shadow_load_a_addr_reg <=
                12'd0;

            shadow_load_a_data_reg <=
                32'd0;

            shadow_load_b_we_reg <=
                1'b0;

            shadow_load_b_addr_reg <=
                12'd0;

            shadow_load_b_data_reg <=
                32'd0;
        end
        else
        begin
            core_load_a_we_reg <=
                1'b0;

            core_load_b_we_reg <=
                1'b0;

            shadow_load_a_we_reg <=
                1'b0;

            shadow_load_b_we_reg <=
                1'b0;

            if (
                input_handshake
                && input_state == INPUT_DIRECT_A
            )
            begin
                core_load_a_we_reg <=
                    1'b1;

                core_load_a_addr_reg <=
                    input_coefficient_index;

                core_load_a_data_reg <=
                    s_axis_tdata;
            end
            else if (
                input_handshake
                && input_state == INPUT_DIRECT_B
            )
            begin
                core_load_b_we_reg <=
                    1'b1;

                core_load_b_addr_reg <=
                    input_coefficient_index;

                core_load_b_data_reg <=
                    s_axis_tdata;
            end

            if (
                input_handshake
                && input_state == INPUT_SHADOW_A
            )
            begin
                shadow_load_a_we_reg <=
                    1'b1;

                shadow_load_a_addr_reg <=
                    input_coefficient_index;

                shadow_load_a_data_reg <=
                    s_axis_tdata;
            end
            else if (
                input_handshake
                && input_state == INPUT_SHADOW_B
            )
            begin
                shadow_load_b_we_reg <=
                    1'b1;

                shadow_load_b_addr_reg <=
                    input_coefficient_index;

                shadow_load_b_data_reg <=
                    s_axis_tdata;
            end
        end
    end

    ntt4096_four_bank_coeff_store shadow_store_a (
        .clk             (clk),
        .reset_n         (reset_n),

        .load_we         (shadow_load_a_we_reg),
        .load_addr       (shadow_load_a_addr_reg),
        .load_data       (shadow_load_a_data_reg),

        .read_valid      (shadow_read_valid),
        .read_addr0      (shadow_read_addr0),
        .read_addr1      (shadow_read_addr1),
        .read_addr2      (shadow_read_addr2),
        .read_addr3      (shadow_read_addr3),

        .read_data_valid (shadow_a_read_data_valid),
        .read_data0      (shadow_a_read_data0),
        .read_data1      (shadow_a_read_data1),
        .read_data2      (shadow_a_read_data2),
        .read_data3      (shadow_a_read_data3),

        .write_valid     (1'b0),
        .write_addr0     (12'd0),
        .write_addr1     (12'd1),
        .write_addr2     (12'd2),
        .write_addr3     (12'd3),
        .write_data0     (32'd0),
        .write_data1     (32'd0),
        .write_data2     (32'd0),
        .write_data3     (32'd0)
    );

    ntt4096_four_bank_coeff_store shadow_store_b (
        .clk             (clk),
        .reset_n         (reset_n),

        .load_we         (shadow_load_b_we_reg),
        .load_addr       (shadow_load_b_addr_reg),
        .load_data       (shadow_load_b_data_reg),

        .read_valid      (shadow_read_valid),
        .read_addr0      (shadow_read_addr0),
        .read_addr1      (shadow_read_addr1),
        .read_addr2      (shadow_read_addr2),
        .read_addr3      (shadow_read_addr3),

        .read_data_valid (shadow_b_read_data_valid),
        .read_data0      (shadow_b_read_data0),
        .read_data1      (shadow_b_read_data1),
        .read_data2      (shadow_b_read_data2),
        .read_data3      (shadow_b_read_data3),

        .write_valid     (1'b0),
        .write_addr0     (12'd0),
        .write_addr1     (12'd1),
        .write_addr2     (12'd2),
        .write_addr3     (12'd3),
        .write_data0     (32'd0),
        .write_data1     (32'd0),
        .write_data2     (32'd0),
        .write_data3     (32'd0)
    );

    ntt4096_four_bank_coeff_store result_store (
        .clk             (clk),
        .reset_n         (reset_n),

        .load_we         (1'b0),
        .load_addr       (12'd0),
        .load_data       (32'd0),

        .read_valid      (result_read_valid),
        .read_addr0      (result_read_addr0),
        .read_addr1      (result_read_addr1),
        .read_addr2      (result_read_addr2),
        .read_addr3      (result_read_addr3),

        .read_data_valid (result_read_data_valid),
        .read_data0      (result_read_data0),
        .read_data1      (unused_result_read_data1),
        .read_data2      (unused_result_read_data2),
        .read_data3      (unused_result_read_data3),

        .write_valid     (handoff_commit_valid),
        .write_addr0     ({handoff_data_group, 2'b00}),
        .write_addr1     ({handoff_data_group, 2'b00} + 12'd1),
        .write_addr2     ({handoff_data_group, 2'b00} + 12'd2),
        .write_addr3     ({handoff_data_group, 2'b00} + 12'd3),
        .write_data0     (core_handoff_read_data0),
        .write_data1     (core_handoff_read_data1),
        .write_data2     (core_handoff_read_data2),
        .write_data3     (core_handoff_read_data3)
    );

    poly_mul4096_dual_butterfly_runtime_profile_handoff_core core (
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
        .handoff_read_data0        (core_handoff_read_data0),
        .handoff_read_data1        (core_handoff_read_data1),
        .handoff_read_data2        (core_handoff_read_data2),
        .handoff_read_data3        (core_handoff_read_data3),

        .handoff_write_valid       (core_handoff_write_valid),
        .handoff_write_base        (core_handoff_write_base),
        .handoff_write_a_data0     (shadow_a_read_data0),
        .handoff_write_a_data1     (shadow_a_read_data1),
        .handoff_write_a_data2     (shadow_a_read_data2),
        .handoff_write_a_data3     (shadow_a_read_data3),
        .handoff_write_b_data0     (shadow_b_read_data0),
        .handoff_write_b_data1     (shadow_b_read_data1),
        .handoff_write_b_data2     (shadow_b_read_data2),
        .handoff_write_b_data3     (shadow_b_read_data3),

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

            profile_index <=
                14'd0;

            input_coefficient_index <=
                12'd0;

            batch_mode <=
                1'b0;

            batch_count <=
                32'd1;

            input_product_index <=
                32'd0;

            protocol_error <=
                1'b0;

            completed_profiles <=
                32'd0;

            completed_prefetches <=
                32'd0;

            profile_words_received <=
                32'd0;

            product_words_received <=
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
                        else if (s_axis_tdata == COMMAND_PROFILE)
                        begin
                            profile_index <=
                                14'd0;

                            profile_words_received <=
                                32'd0;

                            input_state <=
                                INPUT_PROFILE_MODULUS;
                        end
                        else if (s_axis_tdata == COMMAND_PRODUCT)
                        begin
                            batch_mode <=
                                1'b0;

                            batch_count <=
                                32'd1;

                            input_product_index <=
                                32'd0;

                            input_coefficient_index <=
                                12'd0;

                            product_words_received <=
                                32'd0;

                            if (profile_ready)
                            begin
                                input_state <=
                                    INPUT_DIRECT_A;
                            end
                            else
                            begin
                                protocol_error <=
                                    1'b1;

                                input_state <=
                                    INPUT_DISCARD;
                            end
                        end
                        else if (s_axis_tdata == COMMAND_BATCH)
                        begin
                            batch_mode <=
                                1'b1;

                            batch_count <=
                                32'd0;

                            input_product_index <=
                                32'd0;

                            input_coefficient_index <=
                                12'd0;

                            product_words_received <=
                                32'd0;

                            if (profile_ready)
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
                            input_state <=
                                INPUT_PROFILE_PAYLOAD;
                        end
                    end
                end

                INPUT_PROFILE_PAYLOAD:
                begin
                    if (input_handshake)
                    begin
                        profile_words_received <=
                            profile_words_received + 1'b1;

                        if (profile_index == PROFILE_PAYLOAD_WORDS - 1)
                        begin
                            if (s_axis_tlast)
                            begin
                                input_state <=
                                    INPUT_PROFILE_COMMIT;
                            end
                            else
                            begin
                                protocol_error <=
                                    1'b1;

                                input_state <=
                                    INPUT_DISCARD;
                            end
                        end
                        else if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_IDLE;
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
                        if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            batch_mode <=
                                1'b0;

                            input_state <=
                                INPUT_IDLE;
                        end
                        else if (s_axis_tdata == 32'd0)
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_DISCARD;
                        end
                        else
                        begin
                            batch_count <=
                                s_axis_tdata;

                            input_coefficient_index <=
                                12'd0;

                            input_state <=
                                INPUT_DIRECT_A;
                        end
                    end
                end

                INPUT_DIRECT_A:
                begin
                    if (input_handshake)
                    begin
                        product_words_received <=
                            product_words_received + 1'b1;

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
                                INPUT_DIRECT_B;
                        end
                        else
                        begin
                            input_coefficient_index <=
                                input_coefficient_index + 1'b1;
                        end
                    end
                end

                INPUT_DIRECT_B:
                begin
                    if (input_handshake)
                    begin
                        product_words_received <=
                            product_words_received + 1'b1;

                        if (input_coefficient_index == 12'd4095)
                        begin
                            if (final_input_product != s_axis_tlast)
                            begin
                                protocol_error <=
                                    1'b1;

                                if (s_axis_tlast)
                                begin
                                    input_state <=
                                        INPUT_IDLE;
                                end
                                else
                                begin
                                    input_state <=
                                        INPUT_DISCARD;
                                end
                            end
                            else
                            begin
                                input_state <=
                                    INPUT_DIRECT_DRAIN;
                            end
                        end
                        else if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_IDLE;
                        end
                        else
                        begin
                            input_coefficient_index <=
                                input_coefficient_index + 1'b1;
                        end
                    end
                end

                INPUT_DIRECT_DRAIN:
                begin
                    input_product_index <=
                        input_product_index + 1'b1;

                    input_coefficient_index <=
                        12'd0;

                    if (batch_count == 32'd1)
                    begin
                        input_state <=
                            INPUT_WAIT_BATCH_COMPLETE;
                    end
                    else
                    begin
                        input_state <=
                            INPUT_SHADOW_A;
                    end
                end

                INPUT_SHADOW_A:
                begin
                    if (input_handshake)
                    begin
                        product_words_received <=
                            product_words_received + 1'b1;

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
                                INPUT_SHADOW_B;
                        end
                        else
                        begin
                            input_coefficient_index <=
                                input_coefficient_index + 1'b1;
                        end
                    end
                end

                INPUT_SHADOW_B:
                begin
                    if (input_handshake)
                    begin
                        product_words_received <=
                            product_words_received + 1'b1;

                        if (input_coefficient_index == 12'd4095)
                        begin
                            if (final_input_product != s_axis_tlast)
                            begin
                                protocol_error <=
                                    1'b1;

                                if (s_axis_tlast)
                                begin
                                    input_state <=
                                        INPUT_IDLE;
                                end
                                else
                                begin
                                    input_state <=
                                        INPUT_DISCARD;
                                end
                            end
                            else
                            begin
                                input_state <=
                                    INPUT_SHADOW_DRAIN;
                            end
                        end
                        else if (s_axis_tlast)
                        begin
                            protocol_error <=
                                1'b1;

                            input_state <=
                                INPUT_IDLE;
                        end
                        else
                        begin
                            input_coefficient_index <=
                                input_coefficient_index + 1'b1;
                        end
                    end
                end

                INPUT_SHADOW_DRAIN:
                begin
                    completed_prefetches <=
                        completed_prefetches + 1'b1;

                    input_product_index <=
                        input_product_index + 1'b1;

                    input_coefficient_index <=
                        12'd0;

                    if (input_product_index + 1'b1 == batch_count)
                    begin
                        input_state <=
                            INPUT_WAIT_BATCH_COMPLETE;
                    end
                    else
                    begin
                        input_state <=
                            INPUT_WAIT_SHADOW_FREE;
                    end
                end

                INPUT_WAIT_SHADOW_FREE:
                begin
                    if (!shadow_full)
                    begin
                        input_coefficient_index <=
                            12'd0;

                        input_state <=
                            INPUT_SHADOW_A;
                    end
                end

                INPUT_WAIT_BATCH_COMPLETE:
                begin
                    if (batch_complete)
                    begin
                        batch_mode <=
                            1'b0;

                        batch_count <=
                            32'd1;

                        input_product_index <=
                            32'd0;

                        input_state <=
                            INPUT_IDLE;
                    end
                end

                INPUT_DISCARD:
                begin
                    if (input_handshake && s_axis_tlast)
                    begin
                        batch_mode <=
                            1'b0;

                        batch_count <=
                            32'd1;

                        input_product_index <=
                            32'd0;

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
            case ({result_buffer_fill_done, result_buffer_consume})
                2'b10:
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
                end

                2'b11:
                begin
                    result_buffer_full <=
                        1'b1;

                    result_buffer_final <=
                        handoff_final_latched;
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
            exec_state <=
                EXEC_IDLE;

            exec_product_index <=
                32'd0;

            handoff_issue_group <=
                10'd0;

            handoff_data_group <=
                10'd0;

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
        end
        else
        begin
            if (handoff_issue_valid)
            begin
                handoff_data_group <=
                    handoff_issue_group;
            end

            case (exec_state)
                EXEC_IDLE:
                begin
                    if (input_state == INPUT_DIRECT_DRAIN)
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
                        if (handoff_resources_ready)
                        begin
                            handoff_issue_group <=
                                10'd0;

                            handoff_cycle_counter <=
                                32'd0;

                            handoff_final_latched <=
                                final_exec_product;

                            exec_state <=
                                EXEC_HANDOFF_ISSUE;
                        end
                        else
                        begin
                            exec_state <=
                                EXEC_WAIT_RESOURCES;
                        end
                    end
                end

                EXEC_WAIT_RESOURCES:
                begin
                    if (handoff_resources_ready)
                    begin
                        handoff_issue_group <=
                            10'd0;

                        handoff_cycle_counter <=
                            32'd0;

                        handoff_final_latched <=
                            final_exec_product;

                        exec_state <=
                            EXEC_HANDOFF_ISSUE;
                    end
                end

                EXEC_HANDOFF_ISSUE:
                begin
                    handoff_cycle_counter <=
                        handoff_cycle_counter + 1'b1;

                    if (handoff_issue_group == 10'd1023)
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
                    if (handoff_commit_last)
                    begin
                        completed_handoffs <=
                            completed_handoffs + 1'b1;

                        last_handoff_cycles <=
                            handoff_cycle_counter + 1'b1;

                        if (handoff_final_latched)
                        begin
                            exec_product_index <=
                                32'd0;

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

            compute_output_overlap_observed <=
                1'b0;
        end
        else
        begin
            if (core_busy && result_buffer_full)
            begin
                compute_output_overlap_observed <=
                    1'b1;
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

                            output_index <=
                                12'd0;

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
            if (core_start && !profile_ready)
            begin
                $display(
                    "ERROR: buffered adapter started without a profile"
                );

                $fatal(1);
            end

            if (core_load_a_we && core_busy)
            begin
                $display(
                    "ERROR: buffered adapter scalar-wrote core A while busy"
                );

                $fatal(1);
            end

            if (core_load_b_we && core_busy)
            begin
                $display(
                    "ERROR: buffered adapter scalar-wrote core B while busy"
                );

                $fatal(1);
            end

            if (core_handoff_write_valid && core_busy)
            begin
                $display(
                    "ERROR: buffered adapter handoff-wrote core while busy"
                );

                $fatal(1);
            end

            if (shadow_fill_done && shadow_full)
            begin
                $display(
                    "ERROR: attempted to fill an occupied shadow slot"
                );

                $fatal(1);
            end

            if (result_buffer_fill_done && result_buffer_full)
            begin
                $display(
                    "ERROR: attempted to fill an occupied result buffer"
                );

                $fatal(1);
            end

            if (handoff_commit_valid && !core_handoff_read_data_valid)
            begin
                $display(
                    "ERROR: handoff committed without core result data"
                );

                $fatal(1);
            end

        end
    end

`endif

endmodule
