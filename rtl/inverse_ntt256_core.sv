`timescale 1ns/1ps

/*
 * Complete BRAM-backed N=256 inverse negacyclic NTT.
 *
 * Input:
 *
 *     256 natural-order transform coefficients
 *
 * Input placement:
 *
 *     cyclic_memory[bit_reverse(j)] = input[j]
 *
 * Cyclic transform:
 *
 *     radix-2 DIT inverse cyclic NTT using omega^-1
 *
 * Postprocessing:
 *
 *     output[j] =
 *         cyclic_inverse[j]
 *         * N^-1
 *         * psi^-j
 *         mod q
 *
 * Output:
 *
 *     256 natural-order coefficients
 */
module inverse_ntt256_core #(
    parameter INVERSE_TWIDDLE_INIT_FILE =
        "../tests/fixtures/ntt_n256/inverse_twiddles.mem",

    parameter INVERSE_SCALE_INIT_FILE =
        "../tests/fixtures/ntt_n256/inverse_scale_factors.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Natural-order transform loading interface.
     *
     * Accepted only while idle.
     */
    input  logic        load_we,
    input  logic [7:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order recovered-coefficient read interface.
     *
     * Reads are synchronous with one-clock latency.
     */
    input  logic [7:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [8:0]  postprocess_multiplication_count,
    output logic [10:0] butterfly_count
);

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [3:0] {
        STATE_IDLE,

        STATE_INPUT_READ_ISSUE,
        STATE_INPUT_READ_CAPTURE,
        STATE_INPUT_WRITE_BIT_REVERSED,

        STATE_CYCLIC_START,
        STATE_CYCLIC_WAIT,

        STATE_POSTPROCESS_READ_ISSUE,
        STATE_POSTPROCESS_READ_CAPTURE,
        STATE_POSTPROCESS_MULTIPLY_START,
        STATE_POSTPROCESS_MULTIPLY_WAIT,
        STATE_POSTPROCESS_WRITE
    } state_t;

    state_t state;

    logic [7:0] input_index;
    logic [7:0] postprocess_index;

    /*
     * Natural-order input BRAM.
     */
    logic        source_a_enable;
    logic        source_a_write_enable;
    logic [7:0]  source_a_address;
    logic [31:0] source_a_write_data;
    logic [31:0] source_a_read_data;

    logic        source_b_enable;
    logic        source_b_write_enable;
    logic [7:0]  source_b_address;
    logic [31:0] source_b_write_data;
    logic [31:0] source_b_read_data;

    /*
     * Natural-order result BRAM.
     */
    logic        result_a_enable;
    logic        result_a_write_enable;
    logic [7:0]  result_a_address;
    logic [31:0] result_a_write_data;
    logic [31:0] result_a_read_data;

    logic        result_b_enable;
    logic        result_b_write_enable;
    logic [7:0]  result_b_address;
    logic [31:0] result_b_write_data;
    logic [31:0] result_b_read_data;

    /*
     * Value copied from source memory into the cyclic engine.
     */
    logic [31:0] current_input_value;

    /*
     * Inverse cyclic NTT interface.
     */
    logic        cyclic_start;

    logic        cyclic_load_we;
    logic [7:0]  cyclic_load_addr;
    logic [31:0] cyclic_load_data;

    logic [7:0]  cyclic_read_addr;
    logic [31:0] cyclic_read_data;

    logic        cyclic_busy;
    logic        cyclic_done;

    logic [31:0] cyclic_cycles;
    logic [10:0] cyclic_butterfly_count;

    /*
     * Inverse scale-factor ROM:
     *
     *     N^-1 * psi^-j mod q
     */
    logic [7:0]  scale_factor_address;
    logic [31:0] scale_factor_data;

    logic [31:0] current_cyclic_value;
    logic [31:0] current_scale_factor;

    /*
     * Postprocessing modular multiplier.
     */
    logic        postprocess_multiplier_start;
    logic        postprocess_multiplier_busy;
    logic        postprocess_multiplier_done;
    logic [31:0] postprocess_multiplier_result;

    function automatic logic [7:0] bit_reverse8(
        input logic [7:0] value
    );
        begin
            bit_reverse8 = {
                value[0],
                value[1],
                value[2],
                value[3],
                value[4],
                value[5],
                value[6],
                value[7]
            };
        end
    endfunction

    assign read_data =
        result_a_read_data;

    assign cyclic_start =
        state == STATE_CYCLIC_START;

    /*
     * Input coefficients are copied into bit-reversed addresses
     * before launching the radix-2 DIT inverse cyclic transform.
     */
    assign cyclic_load_we =
        state == STATE_INPUT_WRITE_BIT_REVERSED;

    assign cyclic_load_addr =
        bit_reverse8(input_index);

    assign cyclic_load_data =
        current_input_value;

    /*
     * After the cyclic transform, coefficients are already in
     * natural order.
     */
    assign cyclic_read_addr =
        postprocess_index;

    assign scale_factor_address =
        postprocess_index;

    assign postprocess_multiplier_start =
        state == STATE_POSTPROCESS_MULTIPLY_START;

    assign butterfly_count =
        cyclic_butterfly_count;

    /*
     * Input-memory arbitration.
     */
    always @*
    begin
        source_a_enable       = 1'b0;
        source_a_write_enable = 1'b0;
        source_a_address      = 8'd0;
        source_a_write_data   = 32'd0;

        source_b_enable       = 1'b0;
        source_b_write_enable = 1'b0;
        source_b_address      = 8'd0;
        source_b_write_data   = 32'd0;

        if (!busy)
        begin
            source_a_enable =
                1'b1;

            source_a_write_enable =
                load_we;

            source_a_address =
                load_addr;

            source_a_write_data =
                load_data;
        end
        else if (
            state == STATE_INPUT_READ_ISSUE
        )
        begin
            source_a_enable =
                1'b1;

            source_a_address =
                input_index;
        end
    end

    /*
     * Result-memory arbitration.
     */
    always @*
    begin
        result_a_enable       = 1'b0;
        result_a_write_enable = 1'b0;
        result_a_address      = 8'd0;
        result_a_write_data   = 32'd0;

        result_b_enable       = 1'b0;
        result_b_write_enable = 1'b0;
        result_b_address      = 8'd0;
        result_b_write_data   = 32'd0;

        if (!busy)
        begin
            result_a_enable =
                1'b1;

            result_a_address =
                read_addr;
        end
        else if (
            state == STATE_POSTPROCESS_WRITE
        )
        begin
            result_a_enable =
                1'b1;

            result_a_write_enable =
                1'b1;

            result_a_address =
                postprocess_index;

            result_a_write_data =
                postprocess_multiplier_result;
        end
    end

    ntt256_coeff_bram source_memory (
        .clk                 (clk),

        .port_a_enable       (source_a_enable),
        .port_a_write_enable (source_a_write_enable),
        .port_a_address      (source_a_address),
        .port_a_write_data   (source_a_write_data),
        .port_a_read_data    (source_a_read_data),

        .port_b_enable       (source_b_enable),
        .port_b_write_enable (source_b_write_enable),
        .port_b_address      (source_b_address),
        .port_b_write_data   (source_b_write_data),
        .port_b_read_data    (source_b_read_data)
    );

    ntt256_coeff_bram result_memory (
        .clk                 (clk),

        .port_a_enable       (result_a_enable),
        .port_a_write_enable (result_a_write_enable),
        .port_a_address      (result_a_address),
        .port_a_write_data   (result_a_write_data),
        .port_a_read_data    (result_a_read_data),

        .port_b_enable       (result_b_enable),
        .port_b_write_enable (result_b_write_enable),
        .port_b_address      (result_b_address),
        .port_b_write_data   (result_b_write_data),
        .port_b_read_data    (result_b_read_data)
    );

    ntt256_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            INVERSE_TWIDDLE_INIT_FILE
        )
    ) inverse_cyclic_ntt (
        .clk              (clk),
        .reset_n          (reset_n),
        .start            (cyclic_start),

        .load_we          (cyclic_load_we),
        .load_addr        (cyclic_load_addr),
        .load_data        (cyclic_load_data),

        .read_addr        (cyclic_read_addr),
        .read_data        (cyclic_read_data),

        .busy             (cyclic_busy),
        .done             (cyclic_done),

        .cycles           (cyclic_cycles),
        .butterfly_count  (cyclic_butterfly_count)
    );

    ntt256_factor_rom #(
        .INIT_FILE(
            INVERSE_SCALE_INIT_FILE
        )
    ) inverse_scale_rom (
        .clk     (clk),
        .address (scale_factor_address),
        .data    (scale_factor_data)
    );

    modmul_core postprocess_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (postprocess_multiplier_start),

        .a       (current_cyclic_value),
        .b       (current_scale_factor),
        .q       (PROFILE_Q),

        .result  (postprocess_multiplier_result),
        .busy    (postprocess_multiplier_busy),
        .done    (postprocess_multiplier_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            input_index <= 8'd0;
            postprocess_index <= 8'd0;

            current_input_value <= 32'd0;
            current_cyclic_value <= 32'd0;
            current_scale_factor <= 32'd0;

            busy <= 1'b0;
            done <= 1'b0;

            cycles <= 32'd0;

            postprocess_multiplication_count <=
                9'd0;
        end
        else
        begin
            done <= 1'b0;

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start)
                    begin
                        input_index <=
                            8'd0;

                        postprocess_index <=
                            8'd0;

                        postprocess_multiplication_count <=
                            9'd0;

                        cycles <=
                            32'd0;

                        busy <=
                            1'b1;

                        state <=
                            STATE_INPUT_READ_ISSUE;
                    end
                end

                STATE_INPUT_READ_ISSUE:
                begin
                    /*
                     * The source-BRAM read is issued on this edge.
                     */
                    state <=
                        STATE_INPUT_READ_CAPTURE;
                end

                STATE_INPUT_READ_CAPTURE:
                begin
                    current_input_value <=
                        source_a_read_data;

                    state <=
                        STATE_INPUT_WRITE_BIT_REVERSED;
                end

                STATE_INPUT_WRITE_BIT_REVERSED:
                begin
                    /*
                     * The input coefficient is committed to the
                     * inverse cyclic engine on this edge.
                     */
                    if (input_index == 8'd255)
                    begin
                        state <=
                            STATE_CYCLIC_START;
                    end
                    else
                    begin
                        input_index <=
                            input_index + 1'b1;

                        state <=
                            STATE_INPUT_READ_ISSUE;
                    end
                end

                STATE_CYCLIC_START:
                begin
                    /*
                     * cyclic_start is asserted during this state.
                     */
                    state <=
                        STATE_CYCLIC_WAIT;
                end

                STATE_CYCLIC_WAIT:
                begin
                    if (cyclic_done)
                    begin
                        postprocess_index <=
                            8'd0;

                        state <=
                            STATE_POSTPROCESS_READ_ISSUE;
                    end
                end

                STATE_POSTPROCESS_READ_ISSUE:
                begin
                    /*
                     * The cyclic-result BRAM and scale-factor ROM
                     * reads are issued on this edge.
                     */
                    state <=
                        STATE_POSTPROCESS_READ_CAPTURE;
                end

                STATE_POSTPROCESS_READ_CAPTURE:
                begin
                    current_cyclic_value <=
                        cyclic_read_data;

                    current_scale_factor <=
                        scale_factor_data;

                    state <=
                        STATE_POSTPROCESS_MULTIPLY_START;
                end

                STATE_POSTPROCESS_MULTIPLY_START:
                begin
                    /*
                     * postprocess_multiplier_start is asserted during
                     * this state.
                     */
                    state <=
                        STATE_POSTPROCESS_MULTIPLY_WAIT;
                end

                STATE_POSTPROCESS_MULTIPLY_WAIT:
                begin
                    if (postprocess_multiplier_done)
                    begin
                        state <=
                            STATE_POSTPROCESS_WRITE;
                    end
                end

                STATE_POSTPROCESS_WRITE:
                begin
                    /*
                     * The recovered natural-order coefficient is
                     * committed to result memory on this edge.
                     */
                    postprocess_multiplication_count <=
                        postprocess_multiplication_count
                        + 1'b1;

                    if (postprocess_index == 8'd255)
                    begin
                        busy <=
                            1'b0;

                        done <=
                            1'b1;

                        state <=
                            STATE_IDLE;
                    end
                    else
                    begin
                        postprocess_index <=
                            postprocess_index + 1'b1;

                        state <=
                            STATE_POSTPROCESS_READ_ISSUE;
                    end
                end

                default:
                begin
                    state <=
                        STATE_IDLE;

                    busy <=
                        1'b0;
                end
            endcase
        end
    end

endmodule
