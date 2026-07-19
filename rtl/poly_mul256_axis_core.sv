`timescale 1ns/1ps

/*
 * AXI4-Stream adapter for poly_mul256_core.
 *
 * Input frame:
 *
 *     512 x 32-bit words
 *
 *     words   0..255 = polynomial A
 *     words 256..511 = polynomial B
 *
 *     TKEEP must be 4'b1111 on every beat.
 *     TLAST must be asserted only on word 511.
 *
 * Output frame:
 *
 *     256 x 32-bit result words
 *
 *     TLAST is asserted on word 255.
 *
 * The polynomial multiplication starts automatically after the final
 * valid input beat is accepted.
 */
module poly_mul256_axis_core #(
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

    /*
     * AXI4-Stream input from DMA MM2S.
     */
    input  logic [31:0] s_axis_tdata,
    input  logic [3:0]  s_axis_tkeep,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    /*
     * AXI4-Stream output to DMA S2MM.
     */
    output logic [31:0] m_axis_tdata,
    output logic [3:0]  m_axis_tkeep,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,

    /*
     * Status outputs for the later AXI-Lite control/status wrapper.
     */
    output logic        busy,
    output logic        frame_done,
    output logic        protocol_error,

    output logic [31:0] core_cycles,
    output logic [12:0] modular_multiplication_count
);

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
     * Input word index:
     *
     *     bit 8     selects A or B
     *     bits 7:0 select coefficient address
     */
    logic [8:0] input_index;

    logic [7:0] output_index;

    /*
     * Polynomial multiplier interface.
     */
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

    assign s_axis_tready =
        state == STATE_RECEIVE;

    assign core_load_we =
        input_handshake;

    assign core_load_bank =
        input_index[8];

    assign core_load_addr =
        input_index[7:0];

    assign core_load_data =
        s_axis_tdata;

    assign core_start =
        state == STATE_CORE_START;

    assign core_read_addr =
        output_index;

    assign m_axis_tdata =
        output_data_hold;

    assign m_axis_tkeep =
        4'hf;

    assign m_axis_tvalid =
        output_valid_hold;

    assign m_axis_tlast =
        output_valid_hold &&
        (output_index == 8'd255);

    assign busy =
        state != STATE_RECEIVE;

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

    always_ff @(posedge aclk)
    begin
        if (!aresetn)
        begin
            state <=
                STATE_RECEIVE;

            input_index <=
                9'd0;

            output_index <=
                8'd0;

            output_data_hold <=
                32'd0;

            output_valid_hold <=
                1'b0;

            frame_done <=
                1'b0;

            protocol_error <=
                1'b0;
        end
        else
        begin
            frame_done <=
                1'b0;

            case (state)
                STATE_RECEIVE:
                begin
                    output_valid_hold <=
                        1'b0;

                    if (input_handshake)
                    begin
                        /*
                         * Every DMA beat must contain one complete
                         * 32-bit residue.
                         */
                        if (s_axis_tkeep != 4'hf)
                        begin
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_ERROR;
                        end
                        else if (
                            (input_index != 9'd511) &&
                            s_axis_tlast
                        )
                        begin
                            /*
                             * Early packet termination.
                             */
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_ERROR;
                        end
                        else if (
                            (input_index == 9'd511) &&
                            !s_axis_tlast
                        )
                        begin
                            /*
                             * The final input beat must carry TLAST.
                             */
                            protocol_error <=
                                1'b1;

                            state <=
                                STATE_ERROR;
                        end
                        else if (input_index == 9'd511)
                        begin
                            input_index <=
                                9'd0;

                            state <=
                                STATE_CORE_START;
                        end
                        else
                        begin
                            input_index <=
                                input_index + 1'b1;
                        end
                    end
                end

                STATE_CORE_START:
                begin
                    /*
                     * core_start is asserted for this clock.
                     */
                    state <=
                        STATE_CORE_WAIT;
                end

                STATE_CORE_WAIT:
                begin
                    if (core_done)
                    begin
                        output_index <=
                            8'd0;

                        state <=
                            STATE_OUTPUT_READ_ISSUE;
                    end
                end

                STATE_OUTPUT_READ_ISSUE:
                begin
                    /*
                     * The synchronous result-BRAM read is issued on
                     * this edge.
                     */
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
                    /*
                     * Hold TDATA, TKEEP, TVALID, and TLAST unchanged
                     * for any number of DMA backpressure clocks.
                     */
                    if (output_handshake)
                    begin
                        output_valid_hold <=
                            1'b0;

                        if (output_index == 8'd255)
                        begin
                            input_index <=
                                9'd0;

                            frame_done <=
                                1'b1;

                            state <=
                                STATE_RECEIVE;
                        end
                        else
                        begin
                            output_index <=
                                output_index + 1'b1;

                            state <=
                                STATE_OUTPUT_READ_ISSUE;
                        end
                    end
                end

                STATE_ERROR:
                begin
                    /*
                     * A malformed DMA frame requires reset. This is
                     * deliberately fail-closed so a shifted packet
                     * cannot silently produce a wrong polynomial.
                     */
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
