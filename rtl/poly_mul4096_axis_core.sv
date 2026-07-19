`timescale 1ns/1ps

/*
 * AXI4-Stream adapter for one complete N=4096 polynomial product.
 *
 * Input frame:
 *
 *     words    0..4095 : A[0..4095]
 *     words 4096..8191 : B[0..4095]
 *     TLAST             : asserted only on B[4095]
 *
 * Output frame:
 *
 *     words 0..4095     : C[0..4095]
 *     TLAST             : asserted only on C[4095]
 *
 * The adapter accepts a new frame after the previous result frame has
 * been completely consumed. Output data and TLAST remain stable under
 * backpressure.
 *
 * A malformed input TLAST is fail-closed: protocol_error is asserted
 * and input acceptance stops until reset.
 */
module poly_mul4096_axis_core (
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
    output logic [31:0] completed_products,
    output logic [31:0] core_cycles,
    output logic [16:0] modular_multiplications
);

    localparam integer INPUT_WORDS =
        8192;

    localparam integer OUTPUT_WORDS =
        4096;

    typedef enum logic [2:0] {
        STATE_INPUT,
        STATE_CORE_START,
        STATE_CORE_WAIT,
        STATE_OUTPUT_READ_ISSUE,
        STATE_OUTPUT_READ_CAPTURE,
        STATE_OUTPUT_SEND
    } state_t;

    state_t state;

    logic [13:0] input_word_index;
    logic [11:0] output_word_index;

    logic core_start;

    logic core_load_a_we;
    logic core_load_b_we;

    logic [11:0] core_load_a_addr;
    logic [11:0] core_load_b_addr;

    logic [11:0] core_read_addr;
    logic [31:0] core_read_data;

    logic core_busy;
    logic core_done;

    logic [31:0] core_cycles_internal;
    logic [16:0] core_multiplications_internal;

    logic [31:0] unused_forward_cycles;
    logic [31:0] unused_pointwise_cycles;
    logic [31:0] unused_inverse_cycles;

    logic [31:0] output_data_register;

    logic input_handshake;
    logic output_handshake;

    assign s_axis_tready =
        state == STATE_INPUT
        && !protocol_error;

    assign input_handshake =
        s_axis_tvalid
        && s_axis_tready;

    assign core_load_a_we =
        input_handshake
        && input_word_index < 14'd4096;

    assign core_load_b_we =
        input_handshake
        && input_word_index >= 14'd4096;

    /*
     * For B words 4096..8191, the low twelve bits are exactly the
     * coefficient address 0..4095.
     */
    assign core_load_a_addr =
        input_word_index[11:0];

    assign core_load_b_addr =
        input_word_index[11:0];

    assign core_start =
        state == STATE_CORE_START;

    assign core_read_addr =
        output_word_index;

    assign m_axis_tdata =
        output_data_register;

    assign m_axis_tvalid =
        state == STATE_OUTPUT_SEND;

    assign m_axis_tlast =
        state == STATE_OUTPUT_SEND
        && output_word_index == OUTPUT_WORDS - 1;

    assign output_handshake =
        m_axis_tvalid
        && m_axis_tready;

    poly_mul4096_core core (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (core_start),

        .load_a_we            (core_load_a_we),
        .load_a_addr          (core_load_a_addr),
        .load_a_data          (s_axis_tdata),

        .load_b_we            (core_load_b_we),
        .load_b_addr          (core_load_b_addr),
        .load_b_data          (s_axis_tdata),

        .read_addr            (core_read_addr),
        .read_data            (core_read_data),

        .busy                 (core_busy),
        .done                 (core_done),

        .cycles               (core_cycles_internal),
        .multiplication_count (core_multiplications_internal),

        .forward_cycles       (unused_forward_cycles),
        .pointwise_cycles     (unused_pointwise_cycles),
        .inverse_cycles       (unused_inverse_cycles)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_INPUT;

            input_word_index <=
                14'd0;

            output_word_index <=
                12'd0;

            output_data_register <=
                32'd0;

            protocol_error <=
                1'b0;

            completed_products <=
                32'd0;

            core_cycles <=
                32'd0;

            modular_multiplications <=
                17'd0;
        end
        else
        begin
            case (state)
                STATE_INPUT:
                begin
                    if (input_handshake)
                    begin
                        if (
                            input_word_index
                            == INPUT_WORDS - 1
                        )
                        begin
                            if (!s_axis_tlast)
                            begin
                                protocol_error <=
                                    1'b1;
                            end
                            else
                            begin
                                state <=
                                    STATE_CORE_START;
                            end
                        end
                        else
                        begin
                            if (s_axis_tlast)
                            begin
                                protocol_error <=
                                    1'b1;
                            end
                            else
                            begin
                                input_word_index <=
                                    input_word_index + 1'b1;
                            end
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
                        core_cycles <=
                            core_cycles_internal;

                        modular_multiplications <=
                            core_multiplications_internal;

                        output_word_index <=
                            12'd0;

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
                    output_data_register <=
                        core_read_data;

                    state <=
                        STATE_OUTPUT_SEND;
                end

                STATE_OUTPUT_SEND:
                begin
                    if (output_handshake)
                    begin
                        if (
                            output_word_index
                            == OUTPUT_WORDS - 1
                        )
                        begin
                            completed_products <=
                                completed_products + 1'b1;

                            input_word_index <=
                                14'd0;

                            output_word_index <=
                                12'd0;

                            state <=
                                STATE_INPUT;
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

                default:
                begin
                    state <=
                        STATE_INPUT;

                    input_word_index <=
                        14'd0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            state == STATE_CORE_START
            && core_busy
        )
        begin
            $display(
                "ERROR: N=4096 streamed product start attempted while core is busy"
            );

            $fatal(1);
        end

        if (
            state != STATE_INPUT
            && input_handshake
        )
        begin
            $display(
                "ERROR: N=4096 streamed input accepted outside input state"
            );

            $fatal(1);
        end
    end

`endif

endmodule
