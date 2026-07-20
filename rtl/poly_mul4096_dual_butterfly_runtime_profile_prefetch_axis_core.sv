`timescale 1ns/1ps

/*
 * Runtime-profile AXI4-Stream adapter with one-product operand prefetch.
 *
 * Product zero is loaded directly into the unchanged arithmetic stores.
 * While product k computes, product k+1 is accepted into two four-bank
 * shadow stores.  While result k is emitted, shadow A[k+1] and B[k+1]
 * are copied into the arithmetic stores at the SAME logical address
 * after that result address has already been captured.
 *
 * Same-address read-then-write is intentional.  Reverse-address refill
 * would overwrite results that have not yet been emitted.
 *
 * The arithmetic FSM, modular multipliers, profile memories, and exact
 * 631810-cycle hardware schedule are unchanged.  The only arithmetic-
 * core source change keeps the idle A read port enabled during an
 * external load; the underlying coefficient RAMs already have separate
 * synchronous read and write ports.
 */
module poly_mul4096_dual_butterfly_runtime_profile_prefetch_axis_core (
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

    typedef enum logic [3:0] {
        EXEC_IDLE,
        EXEC_START_FIRST,
        EXEC_WAIT_CORE,
        EXEC_WAIT_SHADOW,
        EXEC_OUTPUT_ISSUE,
        EXEC_OUTPUT_SEND,
        EXEC_REFILL_DRAIN,
        EXEC_START_NEXT
    } exec_state_t;

    input_state_t input_state;
    exec_state_t  exec_state;

    logic [13:0] profile_index;
    logic [11:0] input_coefficient_index;
    logic [11:0] output_index;

    logic        batch_mode;
    logic [31:0] batch_count;
    logic [31:0] input_product_index;
    logic [31:0] exec_product_index;

    logic input_handshake;
    logic output_handshake;

    logic final_input_product;
    logic final_exec_product;
    logic refill_output_product;

    logic shadow_full;
    logic shadow_fill_done;
    logic shadow_consume;
    logic batch_complete;

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

    logic [11:0] core_read_a_addr;
    logic [31:0] core_read_a_data;
    logic [31:0] unused_core_read_b_data;

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
    logic [31:0] unused_shadow_a_read_data1;
    logic [31:0] unused_shadow_a_read_data2;
    logic [31:0] unused_shadow_a_read_data3;

    logic shadow_b_read_data_valid;
    logic [31:0] shadow_b_read_data0;
    logic [31:0] unused_shadow_b_read_data1;
    logic [31:0] unused_shadow_b_read_data2;
    logic [31:0] unused_shadow_b_read_data3;

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

    assign refill_output_product =
        !final_exec_product;

    assign shadow_fill_done =
        input_state == INPUT_SHADOW_DRAIN;

    assign shadow_consume =
        exec_state == EXEC_OUTPUT_SEND
        && output_handshake
        && output_index == 12'd4095
        && refill_output_product;

    assign batch_complete =
        exec_state == EXEC_OUTPUT_SEND
        && output_handshake
        && output_index == 12'd4095
        && final_exec_product;

    assign accelerator_busy =
        core_busy
        || input_state != INPUT_IDLE
        || exec_state != EXEC_IDLE
        || shadow_full;

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
        || exec_state == EXEC_START_NEXT;

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

    assign core_read_a_addr =
        output_index;

    assign m_axis_tdata =
        core_read_a_data;

    assign m_axis_tvalid =
        exec_state == EXEC_OUTPUT_SEND;

    assign m_axis_tlast =
        exec_state == EXEC_OUTPUT_SEND
        && output_index == 12'd4095
        && final_exec_product;

    assign shadow_read_valid =
        exec_state == EXEC_OUTPUT_ISSUE
        && refill_output_product;

    assign shadow_read_addr0 =
        output_index;

    assign shadow_read_addr1 = {
        output_index[11:2],
        output_index[1:0] + 2'd1
    };

    assign shadow_read_addr2 = {
        output_index[11:2],
        output_index[1:0] + 2'd2
    };

    assign shadow_read_addr3 = {
        output_index[11:2],
        output_index[1:0] + 2'd3
    };

    /*
     * Registered write boundaries preserve the timing isolation already
     * proven by the batch-of-two overlay.  During refill, the write from
     * result i is committed in the following EXEC_OUTPUT_ISSUE cycle,
     * while result i+1 is read through the independent BRAM read port.
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
            else if (
                exec_state == EXEC_OUTPUT_SEND
                && output_handshake
                && refill_output_product
            )
            begin
                core_load_a_we_reg <=
                    1'b1;

                core_load_a_addr_reg <=
                    output_index;

                core_load_a_data_reg <=
                    shadow_a_read_data0;

                core_load_b_we_reg <=
                    1'b1;

                core_load_b_addr_reg <=
                    output_index;

                core_load_b_data_reg <=
                    shadow_b_read_data0;
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
        .read_data1      (unused_shadow_a_read_data1),
        .read_data2      (unused_shadow_a_read_data2),
        .read_data3      (unused_shadow_a_read_data3),

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
        .read_data1      (unused_shadow_b_read_data1),
        .read_data2      (unused_shadow_b_read_data2),
        .read_data3      (unused_shadow_b_read_data3),

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
        .read_b_data               (unused_core_read_b_data),

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
            exec_state <=
                EXEC_IDLE;

            exec_product_index <=
                32'd0;

            output_index <=
                12'd0;

            completed_products <=
                32'd0;

            completed_batches <=
                32'd0;

            completed_refills <=
                32'd0;
        end
        else
        begin
            case (exec_state)
                EXEC_IDLE:
                begin
                    if (input_state == INPUT_DIRECT_DRAIN)
                    begin
                        exec_product_index <=
                            32'd0;

                        output_index <=
                            12'd0;

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
                        output_index <=
                            12'd0;

                        if (final_exec_product || shadow_full)
                        begin
                            exec_state <=
                                EXEC_OUTPUT_ISSUE;
                        end
                        else
                        begin
                            exec_state <=
                                EXEC_WAIT_SHADOW;
                        end
                    end
                end

                EXEC_WAIT_SHADOW:
                begin
                    if (shadow_full)
                    begin
                        output_index <=
                            12'd0;

                        exec_state <=
                            EXEC_OUTPUT_ISSUE;
                    end
                end

                EXEC_OUTPUT_ISSUE:
                begin
                    exec_state <=
                        EXEC_OUTPUT_SEND;
                end

                EXEC_OUTPUT_SEND:
                begin
                    if (output_handshake)
                    begin
                        if (output_index == 12'd4095)
                        begin
                            completed_products <=
                                completed_products + 1'b1;

                            if (final_exec_product)
                            begin
                                if (batch_mode)
                                begin
                                    completed_batches <=
                                        completed_batches + 1'b1;
                                end

                                exec_product_index <=
                                    32'd0;

                                output_index <=
                                    12'd0;

                                exec_state <=
                                    EXEC_IDLE;
                            end
                            else
                            begin
                                exec_product_index <=
                                    exec_product_index + 1'b1;

                                output_index <=
                                    12'd0;

                                exec_state <=
                                    EXEC_REFILL_DRAIN;
                            end
                        end
                        else
                        begin
                            output_index <=
                                output_index + 1'b1;

                            exec_state <=
                                EXEC_OUTPUT_ISSUE;
                        end
                    end
                end

                EXEC_REFILL_DRAIN:
                begin
                    completed_refills <=
                        completed_refills + 1'b1;

                    exec_state <=
                        EXEC_START_NEXT;
                end

                EXEC_START_NEXT:
                begin
                    exec_state <=
                        EXEC_WAIT_CORE;
                end

                default:
                begin
                    exec_state <=
                        EXEC_IDLE;
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
                    "ERROR: prefetch adapter started without a profile"
                );

                $fatal(1);
            end

            if (core_load_a_we && core_busy)
            begin
                $display(
                    "ERROR: prefetch adapter wrote core A while busy"
                );

                $fatal(1);
            end

            if (core_load_b_we && core_busy)
            begin
                $display(
                    "ERROR: prefetch adapter wrote core B while busy"
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
        end
    end

`endif

endmodule
