`timescale 1ns/1ps

/*
 * Complete BRAM-backed N=256 forward negacyclic NTT.
 *
 * Input:
 *
 *     256 natural-order coefficients
 *
 * Preprocessing:
 *
 *     twisted[j] = input[j] * psi^j mod q
 *
 *     cyclic_memory[bit_reverse(j)] = twisted[j]
 *
 * Transform:
 *
 *     radix-2 DIT cyclic NTT using omega
 *
 * Output:
 *
 *     256 natural-order transform coefficients
 */
module forward_ntt256_core #(
    parameter TWIST_INIT_FILE =
        "../tests/fixtures/ntt_n256/twist_factors.mem",

    parameter TWIDDLE_INIT_FILE =
        "../tests/fixtures/ntt_n256/forward_twiddles.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Natural-order source loading interface.
     *
     * Accepted only while idle.
     */
    input  logic        load_we,
    input  logic [7:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order transform read interface.
     *
     * Reads are synchronous with one-clock latency.
     */
    input  logic [7:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [8:0]  preprocess_multiplication_count,
    output logic [10:0] butterfly_count
);

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PREPROCESS_READ_ISSUE,
        STATE_PREPROCESS_READ_CAPTURE,
        STATE_PREPROCESS_MULTIPLY_START,
        STATE_PREPROCESS_MULTIPLY_WAIT,
        STATE_PREPROCESS_WRITE,
        STATE_CYCLIC_START,
        STATE_CYCLIC_WAIT
    } state_t;

    state_t state;

    logic [7:0] preprocess_index;

    /*
     * Natural-order source BRAM.
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
     * Twist-factor ROM.
     */
    logic [7:0]  factor_address;
    logic [31:0] factor_data;

    logic [31:0] current_source_value;
    logic [31:0] current_factor;

    /*
     * Preprocessing modular multiplier.
     */
    logic        preprocess_multiplier_start;
    logic        preprocess_multiplier_busy;
    logic        preprocess_multiplier_done;
    logic [31:0] preprocess_multiplier_result;

    /*
     * Cyclic NTT interface.
     */
    logic        cyclic_start;

    logic        cyclic_load_we;
    logic [7:0]  cyclic_load_addr;
    logic [31:0] cyclic_load_data;

    logic [31:0] cyclic_read_data;

    logic        cyclic_busy;
    logic        cyclic_done;

    logic [31:0] cyclic_cycles;
    logic [10:0] cyclic_butterfly_count;

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
        cyclic_read_data;

    assign factor_address =
        preprocess_index;

    assign preprocess_multiplier_start =
        state == STATE_PREPROCESS_MULTIPLY_START;

    assign cyclic_start =
        state == STATE_CYCLIC_START;

    assign cyclic_load_we =
        state == STATE_PREPROCESS_WRITE;

    assign cyclic_load_addr =
        bit_reverse8(preprocess_index);

    assign cyclic_load_data =
        preprocess_multiplier_result;

    assign butterfly_count =
        cyclic_butterfly_count;

    /*
     * Source-BRAM port arbitration.
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
            state == STATE_PREPROCESS_READ_ISSUE
        )
        begin
            source_a_enable =
                1'b1;

            source_a_address =
                preprocess_index;
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

    ntt256_factor_rom #(
        .INIT_FILE(
            TWIST_INIT_FILE
        )
    ) twist_factor_rom (
        .clk     (clk),
        .address (factor_address),
        .data    (factor_data)
    );

    modmul_core preprocess_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (preprocess_multiplier_start),

        .a       (current_source_value),
        .b       (current_factor),
        .q       (PROFILE_Q),

        .result  (preprocess_multiplier_result),
        .busy    (preprocess_multiplier_busy),
        .done    (preprocess_multiplier_done)
    );

    ntt256_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            TWIDDLE_INIT_FILE
        )
    ) cyclic_ntt (
        .clk              (clk),
        .reset_n          (reset_n),
        .start            (cyclic_start),

        .load_we          (cyclic_load_we),
        .load_addr        (cyclic_load_addr),
        .load_data        (cyclic_load_data),

        .read_addr        (read_addr),
        .read_data        (cyclic_read_data),

        .busy             (cyclic_busy),
        .done             (cyclic_done),

        .cycles           (cyclic_cycles),
        .butterfly_count  (cyclic_butterfly_count)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            preprocess_index <= 8'd0;

            current_source_value <= 32'd0;
            current_factor <= 32'd0;

            busy <= 1'b0;
            done <= 1'b0;

            cycles <= 32'd0;

            preprocess_multiplication_count <=
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
                        preprocess_index <=
                            8'd0;

                        preprocess_multiplication_count <=
                            9'd0;

                        cycles <=
                            32'd0;

                        busy <=
                            1'b1;

                        state <=
                            STATE_PREPROCESS_READ_ISSUE;
                    end
                end

                STATE_PREPROCESS_READ_ISSUE:
                begin
                    /*
                     * Source BRAM and factor-ROM reads are issued on
                     * this rising edge.
                     */
                    state <=
                        STATE_PREPROCESS_READ_CAPTURE;
                end

                STATE_PREPROCESS_READ_CAPTURE:
                begin
                    /*
                     * Synchronous BRAM and ROM outputs are now valid.
                     */
                    current_source_value <=
                        source_a_read_data;

                    current_factor <=
                        factor_data;

                    state <=
                        STATE_PREPROCESS_MULTIPLY_START;
                end

                STATE_PREPROCESS_MULTIPLY_START:
                begin
                    /*
                     * preprocess_multiplier_start is asserted during
                     * this state.
                     */
                    state <=
                        STATE_PREPROCESS_MULTIPLY_WAIT;
                end

                STATE_PREPROCESS_MULTIPLY_WAIT:
                begin
                    if (preprocess_multiplier_done)
                    begin
                        state <=
                            STATE_PREPROCESS_WRITE;
                    end
                end

                STATE_PREPROCESS_WRITE:
                begin
                    /*
                     * The twisted coefficient is committed to the
                     * cyclic engine at the bit-reversed address on
                     * this edge.
                     */
                    preprocess_multiplication_count <=
                        preprocess_multiplication_count
                        + 1'b1;

                    if (preprocess_index == 8'd255)
                    begin
                        state <=
                            STATE_CYCLIC_START;
                    end
                    else
                    begin
                        preprocess_index <=
                            preprocess_index + 1'b1;

                        state <=
                            STATE_PREPROCESS_READ_ISSUE;
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
                        busy <=
                            1'b0;

                        done <=
                            1'b1;

                        state <=
                            STATE_IDLE;
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
