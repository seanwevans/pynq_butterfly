`timescale 1ns/1ps

/*
 * BRAM-backed 256-coefficient pointwise modular multiplier.
 *
 * For every transform-domain coefficient:
 *
 *     result[j] = input_a[j] * input_b[j] mod q
 *
 * The two input vectors and result vector are stored in separate
 * 256 x 32-bit BRAMs.
 *
 * External loading and result reads are available only while idle.
 * Result reads are synchronous with one-clock latency.
 */
module pointwise_mul256_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Input loading interface.
     *
     * load_bank = 0 selects transform A.
     * load_bank = 1 selects transform B.
     */
    input  logic        load_we,
    input  logic        load_bank,
    input  logic [7:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order result read interface.
     */
    input  logic [7:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [8:0]  multiplication_count
);

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_READ_ISSUE,
        STATE_READ_CAPTURE,
        STATE_MULTIPLY_START,
        STATE_MULTIPLY_WAIT,
        STATE_WRITEBACK
    } state_t;

    state_t state;

    logic [7:0] coefficient_index;

    /*
     * Input-A BRAM signals.
     */
    logic        input_a_enable;
    logic        input_a_write_enable;
    logic [7:0]  input_a_address;
    logic [31:0] input_a_write_data;
    logic [31:0] input_a_read_data;

    /*
     * Input-B BRAM signals.
     */
    logic        input_b_enable;
    logic        input_b_write_enable;
    logic [7:0]  input_b_address;
    logic [31:0] input_b_write_data;
    logic [31:0] input_b_read_data;

    /*
     * Result BRAM signals.
     */
    logic        result_enable;
    logic        result_write_enable;
    logic [7:0]  result_address;
    logic [31:0] result_write_data;
    logic [31:0] result_read_data;

    logic unused_a_enable;
    logic unused_a_write_enable;
    logic [7:0] unused_a_address;
    logic [31:0] unused_a_write_data;
    logic [31:0] unused_a_read_data;

    logic unused_b_enable;
    logic unused_b_write_enable;
    logic [7:0] unused_b_address;
    logic [31:0] unused_b_write_data;
    logic [31:0] unused_b_read_data;

    logic unused_result_enable;
    logic unused_result_write_enable;
    logic [7:0] unused_result_address;
    logic [31:0] unused_result_write_data;
    logic [31:0] unused_result_read_data;

    /*
     * Current operand registers.
     */
    logic [31:0] current_a;
    logic [31:0] current_b;

    /*
     * Existing verified modular multiplier.
     */
    logic        multiplier_start;
    logic        multiplier_busy;
    logic        multiplier_done;
    logic [31:0] multiplier_result;

    assign read_data =
        result_read_data;

    assign multiplier_start =
        state == STATE_MULTIPLY_START;

    /*
     * Input-A BRAM arbitration.
     */
    always @*
    begin
        input_a_enable       = 1'b0;
        input_a_write_enable = 1'b0;
        input_a_address      = 8'd0;
        input_a_write_data   = 32'd0;

        if (!busy)
        begin
            if (load_we && !load_bank)
            begin
                input_a_enable =
                    1'b1;

                input_a_write_enable =
                    1'b1;

                input_a_address =
                    load_addr;

                input_a_write_data =
                    load_data;
            end
        end
        else if (state == STATE_READ_ISSUE)
        begin
            input_a_enable =
                1'b1;

            input_a_address =
                coefficient_index;
        end
    end

    /*
     * Input-B BRAM arbitration.
     */
    always @*
    begin
        input_b_enable       = 1'b0;
        input_b_write_enable = 1'b0;
        input_b_address      = 8'd0;
        input_b_write_data   = 32'd0;

        if (!busy)
        begin
            if (load_we && load_bank)
            begin
                input_b_enable =
                    1'b1;

                input_b_write_enable =
                    1'b1;

                input_b_address =
                    load_addr;

                input_b_write_data =
                    load_data;
            end
        end
        else if (state == STATE_READ_ISSUE)
        begin
            input_b_enable =
                1'b1;

            input_b_address =
                coefficient_index;
        end
    end

    /*
     * Result BRAM arbitration.
     */
    always @*
    begin
        result_enable       = 1'b0;
        result_write_enable = 1'b0;
        result_address      = 8'd0;
        result_write_data   = 32'd0;

        if (!busy)
        begin
            result_enable =
                1'b1;

            result_address =
                read_addr;
        end
        else if (state == STATE_WRITEBACK)
        begin
            result_enable =
                1'b1;

            result_write_enable =
                1'b1;

            result_address =
                coefficient_index;

            result_write_data =
                multiplier_result;
        end
    end

    /*
     * Port B of each memory is intentionally unused. Keeping the
     * shared true-dual-port template allows later parallelization.
     */
    assign unused_a_enable =
        1'b0;

    assign unused_a_write_enable =
        1'b0;

    assign unused_a_address =
        8'd0;

    assign unused_a_write_data =
        32'd0;

    assign unused_b_enable =
        1'b0;

    assign unused_b_write_enable =
        1'b0;

    assign unused_b_address =
        8'd0;

    assign unused_b_write_data =
        32'd0;

    assign unused_result_enable =
        1'b0;

    assign unused_result_write_enable =
        1'b0;

    assign unused_result_address =
        8'd0;

    assign unused_result_write_data =
        32'd0;

    ntt256_coeff_bram input_a_memory (
        .clk                 (clk),

        .port_a_enable       (input_a_enable),
        .port_a_write_enable (input_a_write_enable),
        .port_a_address      (input_a_address),
        .port_a_write_data   (input_a_write_data),
        .port_a_read_data    (input_a_read_data),

        .port_b_enable       (unused_a_enable),
        .port_b_write_enable (unused_a_write_enable),
        .port_b_address      (unused_a_address),
        .port_b_write_data   (unused_a_write_data),
        .port_b_read_data    (unused_a_read_data)
    );

    ntt256_coeff_bram input_b_memory (
        .clk                 (clk),

        .port_a_enable       (input_b_enable),
        .port_a_write_enable (input_b_write_enable),
        .port_a_address      (input_b_address),
        .port_a_write_data   (input_b_write_data),
        .port_a_read_data    (input_b_read_data),

        .port_b_enable       (unused_b_enable),
        .port_b_write_enable (unused_b_write_enable),
        .port_b_address      (unused_b_address),
        .port_b_write_data   (unused_b_write_data),
        .port_b_read_data    (unused_b_read_data)
    );

    ntt256_coeff_bram result_memory (
        .clk                 (clk),

        .port_a_enable       (result_enable),
        .port_a_write_enable (result_write_enable),
        .port_a_address      (result_address),
        .port_a_write_data   (result_write_data),
        .port_a_read_data    (result_read_data),

        .port_b_enable       (unused_result_enable),
        .port_b_write_enable (unused_result_write_enable),
        .port_b_address      (unused_result_address),
        .port_b_write_data   (unused_result_write_data),
        .port_b_read_data    (unused_result_read_data)
    );

    modmul_core multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (multiplier_start),

        .a       (current_a),
        .b       (current_b),
        .q       (PROFILE_Q),

        .result  (multiplier_result),
        .busy    (multiplier_busy),
        .done    (multiplier_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_IDLE;

            coefficient_index <=
                8'd0;

            current_a <=
                32'd0;

            current_b <=
                32'd0;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            multiplication_count <=
                9'd0;
        end
        else
        begin
            done <=
                1'b0;

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
                        coefficient_index <=
                            8'd0;

                        multiplication_count <=
                            9'd0;

                        cycles <=
                            32'd0;

                        busy <=
                            1'b1;

                        state <=
                            STATE_READ_ISSUE;
                    end
                end

                STATE_READ_ISSUE:
                begin
                    /*
                     * Both input BRAM reads are issued on this edge.
                     */
                    state <=
                        STATE_READ_CAPTURE;
                end

                STATE_READ_CAPTURE:
                begin
                    current_a <=
                        input_a_read_data;

                    current_b <=
                        input_b_read_data;

                    state <=
                        STATE_MULTIPLY_START;
                end

                STATE_MULTIPLY_START:
                begin
                    /*
                     * multiplier_start is asserted during this state.
                     */
                    state <=
                        STATE_MULTIPLY_WAIT;
                end

                STATE_MULTIPLY_WAIT:
                begin
                    if (multiplier_done)
                    begin
                        state <=
                            STATE_WRITEBACK;
                    end
                end

                STATE_WRITEBACK:
                begin
                    /*
                     * The result coefficient is committed to BRAM on
                     * this edge.
                     */
                    multiplication_count <=
                        multiplication_count + 1'b1;

                    if (coefficient_index == 8'd255)
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
                        coefficient_index <=
                            coefficient_index + 1'b1;

                        state <=
                            STATE_READ_ISSUE;
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
