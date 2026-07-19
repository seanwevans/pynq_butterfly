`timescale 1ns/1ps

/*
 * Batched AXI4-Stream adapter for poly_mul256_core.
 *
 * For BATCH_PRODUCTS products, the input packet contains:
 *
 *     product 0: A[0..255], B[0..255]
 *     product 1: A[0..255], B[0..255]
 *     ...
 *
 * TLAST is asserted only on the final B[255] of the final product.
 *
 * The output packet contains:
 *
 *     product 0: C[0..255]
 *     product 1: C[0..255]
 *     ...
 *
 * TLAST is asserted only on the final C[255].
 *
 * The DMA may remain stalled while each product is computed. This
 * permits one large MM2S/S2MM transaction to amortize software setup.
 */
module poly_mul256_axis_batch_core #(
    parameter integer BATCH_PRODUCTS = 32,

    parameter FORWARD_TWIST_INIT_FILE =
        "twist_factors.mem",

    parameter FORWARD_TWIDDLE_INIT_FILE =
        "forward_twiddles.mem",

    parameter INVERSE_TWIDDLE_INIT_FILE =
        "inverse_twiddles.mem",

    parameter INVERSE_SCALE_INIT_FILE =
        "inverse_scale_factors.mem"
) (
    input  logic        aclk,
    input  logic        aresetn,

    input  logic [31:0] s_axis_tdata,
    input  logic [3:0]  s_axis_tkeep,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [31:0] m_axis_tdata,
    output logic [3:0]  m_axis_tkeep,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    output logic        busy,
    output logic        batch_done,
    output logic        protocol_error,

    output logic [31:0] completed_products,
    output logic [31:0] core_cycles,
    output logic [12:0] modular_multiplication_count
);

    localparam integer BATCH_INDEX_WIDTH =
        (BATCH_PRODUCTS <= 1)
        ? 1
        : $clog2(BATCH_PRODUCTS);

    typedef enum logic [3:0] {
        STATE_RECEIVE,
        STATE_CORE_START,
        STATE_CORE_WAIT,
        STATE_OUTPUT_READ_ISSUE,
        STATE_OUTPUT_READ_CAPTURE,
        STATE_OUTPUT_WAIT,
        STATE_ERROR
    } state_t;

    state_t state;

    /*
     * One product contains 512 input words:
     *
     *     0..255   selects A
     *     256..511 selects B
     */
    logic [8:0] input_word_index;

    logic [7:0] output_word_index;

    logic [BATCH_INDEX_WIDTH-1:0] product_index;

    logic        core_start;
    logic        core_load_we;
    logic        core_load_bank;
    logic [7:0]  core_load_addr;
    logic [31:0] core_load_data;

    logic [7:0]  core_read_addr;
    logic [31:0] core_read_data;

    logic core_busy;
    logic core_done;

    logic [31:0] output_data_hold;
    logic        output_valid_hold;

    wire input_handshake =
        s_axis_tvalid &&
        s_axis_tready;

    wire output_handshake =
        m_axis_tvalid &&
        m_axis_tready;

    wire final_product =
        product_index == BATCH_PRODUCTS - 1;

    wire final_input_word =
        input_word_index == 9'd511;

    wire final_output_word =
        output_word_index == 8'd255;

    wire expected_input_tlast =
        final_product &&
        final_input_word;

    assign s_axis_tready =
        state == STATE_RECEIVE;

    assign core_load_we =
        input_handshake;

    assign core_load_bank =
        input_word_index[8];

    assign core_load_addr =
        input_word_index[7:0];

    assign core_load_data =
        s_axis_tdata;

    assign core_start =
        state == STATE_CORE_START;

    assign core_read_addr =
        output_word_index;

    assign m_axis_tdata =
        output_data_hold;

    assign m_axis_tkeep =
        4'hf;

    assign m_axis_tvalid =
        output_valid_hold;

    assign m_axis_tlast =
        output_valid_hold &&
        final_product &&
        final_output_word;

    /*
     * Busy remains asserted across the complete batch, including the
     * receive period between consecutive products.
     */
    assign busy =
        (state != STATE_RECEIVE) ||
        (product_index != 0) ||
        (input_word_index != 0);

    poly_mul256_core #(
        .FORWARD_TWIST_INIT_FILE(
            FORWARD_TWIST_INIT_FILE
        ),

        .FORWARD_TWIDDLE_INIT_FILE(
            FORWARD_TWIDDLE_INIT_FILE
        ),

        .INVERSE_TWIDDLE_INIT_FILE(
            INVERSE_TWIDDLE_INIT_FILE
        ),

        .INVERSE_SCALE_INIT_FILE(
            INVERSE_SCALE_INIT_FILE
        )
    ) polynomial_multiplier (
        .clk                          (aclk),
        .reset_n                      (aresetn),
        .start                        (core_start),

        .load_we                      (core_load_we),
        .load_bank                    (core_load_bank),
        .load_addr                    (core_load_addr),
        .load_data                    (core_load_data),

        .read_addr                    (core_read_addr),
        .read_data                    (core_read_data),

        .busy                         (core_busy),
        .done                         (core_done),

        .cycles                       (core_cycles),

        .modular_multiplication_count (
            modular_multiplication_count
        )
    );

`ifndef SYNTHESIS
    initial
    begin
        if (BATCH_PRODUCTS < 1)
        begin
            $error(
                "BATCH_PRODUCTS must be at least one"
            );
        end
    end
`endif

    always_ff @(posedge aclk)
    begin
        if (!aresetn)
        begin
            state <=
                STATE_RECEIVE;

            input_word_index <=
                9'd0;

            output_word_index <=
                8'd0;

            product_index <=
                '0;

            output_data_hold <=
                32'd0;

            output_valid_hold <=
                1'b0;

            batch_done <=
                1'b0;

            protocol_error <=
                1'b0;

            completed_products <=
                32'd0;
        end
        else
        begin
            batch_done <=
                1'b0;

            case (state)
                STATE_RECEIVE:
                begin
                    output_valid_hold <=
                        1'b0;

                    if (input_handshake)
                    begin
                        if (s_axis_tkeep != 4'hf)
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_ERROR;
                        end
                        else if (
                            s_axis_tlast != expected_input_tlast
                        )
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_ERROR;
                        end
                        else if (final_input_word)
                        begin
                            input_word_index <=
                                9'd0;

                            state <=
                                STATE_CORE_START;
                        end
                        else
                        begin
                            input_word_index <=
                                input_word_index + 1'b1;
                        end
                    end
                end

                STATE_CORE_START:
                begin
                    state <=
                        STATE_CORE_WAIT;
                end

                STATE_CORE_WAIT:
                begin
                    if (core_done)
                    begin
                        output_word_index <=
                            8'd0;

                        state <=
                            STATE_OUTPUT_READ_ISSUE;
                    end
                end

                STATE_OUTPUT_READ_ISSUE:
                begin
                    state <=
                        STATE_OUTPUT_READ_CAPTURE;
                end

                STATE_OUTPUT_READ_CAPTURE:
                begin
                    output_data_hold <=
                        core_read_data;

                    output_valid_hold <=
                        1'b1;

                    state <=
                        STATE_OUTPUT_WAIT;
                end

                STATE_OUTPUT_WAIT:
                begin
                    if (output_handshake)
                    begin
                        output_valid_hold <=
                            1'b0;

                        if (final_output_word)
                        begin
                            completed_products <=
                                completed_products + 1'b1;

                            output_word_index <=
                                8'd0;

                            if (final_product)
                            begin
                                product_index <=
                                    '0;

                                input_word_index <=
                                    9'd0;

                                batch_done <=
                                    1'b1;

                                state <=
                                    STATE_RECEIVE;
                            end
                            else
                            begin
                                product_index <=
                                    product_index + 1'b1;

                                input_word_index <=
                                    9'd0;

                                state <=
                                    STATE_RECEIVE;
                            end
                        end
                        else
                        begin
                            output_word_index <=
                                output_word_index + 1'b1;

                            state <=
                                STATE_OUTPUT_READ_ISSUE;
                        end
                    end
                end

                STATE_ERROR:
                begin
                    output_valid_hold <=
                        1'b0;
                end

                default:
                begin
                    protocol_error <=
                        1'b1;

                    state <=
                        STATE_ERROR;
                end
            endcase
        end
    end

endmodule
