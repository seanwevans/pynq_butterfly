`timescale 1ns/1ps

/*
 * Sequential BRAM-backed N=256 cyclic NTT engine.
 *
 * Contract:
 *
 *   input memory order:  bit-reversed
 *   output memory order: natural
 *   algorithm:           radix-2 DIT
 *
 * One butterfly is executed at a time using the existing
 * butterfly_core and modmul_core.
 *
 * Memory transaction:
 *
 *   1. issue two coefficient reads and one twiddle read
 *   2. capture synchronous read results
 *   3. launch butterfly_core
 *   4. wait for modular multiplication
 *   5. write both results simultaneously
 *   6. advance the schedule
 *
 * The external load/read interface is available only while idle.
 */
module ntt256_cyclic_core #(
    parameter TWIDDLE_INIT_FILE =
        "../model/golden_n256/forward_twiddles.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Idle-time coefficient-memory interface.
     *
     * Reads are synchronous with one-clock latency.
     */
    input  logic        load_we,
    input  logic [7:0]  load_addr,
    input  logic [31:0] load_data,

    input  logic [7:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [10:0] butterfly_count
);

    import ntt256_profile_pkg::*;

    /*
     * Keep the datapath modulus explicit. Icarus was interpreting
     * NTT_Q as an undriven one-bit implicit wire at the instance
     * connection, which propagated X values through every butterfly.
     */
    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_SCHEDULE_START,
        STATE_READ_ISSUE,
        STATE_READ_CAPTURE,
        STATE_BUTTERFLY_START,
        STATE_BUTTERFLY_WAIT,
        STATE_WRITEBACK
    } state_t;

    state_t state;

    /*
     * Dual-port coefficient BRAM signals.
     */
    logic        memory_a_enable;
    logic        memory_a_write_enable;
    logic [7:0]  memory_a_address;
    logic [31:0] memory_a_write_data;
    logic [31:0] memory_a_read_data;

    logic        memory_b_enable;
    logic        memory_b_write_enable;
    logic [7:0]  memory_b_address;
    logic [31:0] memory_b_write_data;
    logic [31:0] memory_b_read_data;

    /*
     * Butterfly schedule signals.
     */
    logic schedule_start;
    logic schedule_advance;

    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;

    logic [9:0] schedule_operation_index;
    logic [2:0] schedule_stage;
    logic [6:0] schedule_butterfly_index;

    logic [7:0] schedule_address_a;
    logic [7:0] schedule_address_b;
    logic [7:0] schedule_twiddle_address;

    /*
     * Synchronous twiddle ROM.
     */
    logic [7:0]  twiddle_address;
    logic [31:0] twiddle_data;

    /*
     * Values retained for the current butterfly.
     */
    logic [9:0] current_operation_index;
    logic [2:0] current_stage;
    logic [6:0] current_butterfly_index;

    logic [7:0] current_address_a;
    logic [7:0] current_address_b;
    logic [7:0] current_twiddle_address;

    logic [31:0] current_value_a;
    logic [31:0] current_value_b;
    logic [31:0] current_twiddle;

    /*
     * Existing verified butterfly datapath.
     */
    logic butterfly_start;
    logic butterfly_busy;
    logic butterfly_done;

    logic [31:0] butterfly_result_a;
    logic [31:0] butterfly_result_b;

    assign read_data =
        memory_a_read_data;

    assign schedule_start =
        state == STATE_SCHEDULE_START;

    assign schedule_advance =
        state == STATE_WRITEBACK;

    assign butterfly_start =
        state == STATE_BUTTERFLY_START;

    /*
     * The schedule remains stable until writeback advances it.
     */
    assign twiddle_address =
        schedule_twiddle_address;

    ntt256_coeff_bram coefficient_memory (
        .clk                 (clk),

        .port_a_enable       (memory_a_enable),
        .port_a_write_enable (memory_a_write_enable),
        .port_a_address      (memory_a_address),
        .port_a_write_data   (memory_a_write_data),
        .port_a_read_data    (memory_a_read_data),

        .port_b_enable       (memory_b_enable),
        .port_b_write_enable (memory_b_write_enable),
        .port_b_address      (memory_b_address),
        .port_b_write_data   (memory_b_write_data),
        .port_b_read_data    (memory_b_read_data)
    );

    ntt256_schedule_core schedule (
        .clk              (clk),
        .reset_n          (reset_n),

        .start            (schedule_start),
        .advance          (schedule_advance),

        .busy             (schedule_busy),
        .valid            (schedule_valid),
        .done             (schedule_done),

        .operation_index  (schedule_operation_index),
        .stage            (schedule_stage),
        .butterfly_index  (schedule_butterfly_index),

        .address_a        (schedule_address_a),
        .address_b        (schedule_address_b),
        .twiddle_address  (schedule_twiddle_address)
    );

    ntt256_twiddle_rom #(
        .INIT_FILE(
            TWIDDLE_INIT_FILE
        )
    ) twiddle_rom (
        .clk     (clk),
        .address (twiddle_address),
        .data    (twiddle_data)
    );

    butterfly_core butterfly (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (butterfly_start),

        .a       (current_value_a),
        .b       (current_value_b),
        .omega   (current_twiddle),
        .q       (PROFILE_Q),

        .out_a   (butterfly_result_a),
        .out_b   (butterfly_result_b),

        .busy    (butterfly_busy),
        .done    (butterfly_done)
    );

    /*
     * Coefficient-memory port arbitration.
     */
    always @*
    begin
        memory_a_enable       = 1'b0;
        memory_a_write_enable = 1'b0;
        memory_a_address      = 8'd0;
        memory_a_write_data   = 32'd0;

        memory_b_enable       = 1'b0;
        memory_b_write_enable = 1'b0;
        memory_b_address      = 8'd0;
        memory_b_write_data   = 32'd0;

        if (!busy)
        begin
            /*
             * Port A becomes the external load/read port while idle.
             */
            memory_a_enable =
                1'b1;

            memory_a_write_enable =
                load_we;

            memory_a_address =
                load_we
                    ? load_addr
                    : read_addr;

            memory_a_write_data =
                load_data;
        end
        else
        begin
            case (state)
                STATE_READ_ISSUE:
                begin
                    memory_a_enable =
                        1'b1;

                    memory_a_address =
                        schedule_address_a;

                    memory_b_enable =
                        1'b1;

                    memory_b_address =
                        schedule_address_b;
                end

                STATE_WRITEBACK:
                begin
                    memory_a_enable =
                        1'b1;

                    memory_a_write_enable =
                        1'b1;

                    memory_a_address =
                        current_address_a;

                    memory_a_write_data =
                        butterfly_result_a;

                    memory_b_enable =
                        1'b1;

                    memory_b_write_enable =
                        1'b1;

                    memory_b_address =
                        current_address_b;

                    memory_b_write_data =
                        butterfly_result_b;
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
            state <= STATE_IDLE;

            busy <= 1'b0;
            done <= 1'b0;

            cycles <= 32'd0;
            butterfly_count <= 11'd0;

            current_operation_index <= 10'd0;
            current_stage <= 3'd0;
            current_butterfly_index <= 7'd0;

            current_address_a <= 8'd0;
            current_address_b <= 8'd0;
            current_twiddle_address <= 8'd0;

            current_value_a <= 32'd0;
            current_value_b <= 32'd0;
            current_twiddle <= 32'd0;
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
                        busy <= 1'b1;

                        cycles <= 32'd0;
                        butterfly_count <= 11'd0;

                        state <= STATE_SCHEDULE_START;
                    end
                end

                STATE_SCHEDULE_START:
                begin
                    /*
                     * schedule_start is asserted for this clock.
                     */
                    state <= STATE_READ_ISSUE;
                end

                STATE_READ_ISSUE:
                begin
`ifndef SYNTHESIS
                    if (
                        !schedule_valid ||
                        !schedule_busy
                    )
                    begin
                        $display(
                            "ERROR: NTT schedule invalid during read issue"
                        );

                        $fatal(1);
                    end
`endif

                    /*
                     * Preserve addresses and identity for writeback.
                     *
                     * Coefficient BRAM and twiddle ROM reads are
                     * issued on this same rising edge.
                     */
                    current_operation_index <=
                        schedule_operation_index;

                    current_stage <=
                        schedule_stage;

                    current_butterfly_index <=
                        schedule_butterfly_index;

                    current_address_a <=
                        schedule_address_a;

                    current_address_b <=
                        schedule_address_b;

                    current_twiddle_address <=
                        schedule_twiddle_address;

                    state <= STATE_READ_CAPTURE;
                end

                STATE_READ_CAPTURE:
                begin
                    /*
                     * The synchronous BRAM and ROM outputs have been
                     * stable since the preceding rising edge.
                     */
                    current_value_a <=
                        memory_a_read_data;

                    current_value_b <=
                        memory_b_read_data;

                    current_twiddle <=
                        twiddle_data;

                    state <= STATE_BUTTERFLY_START;
                end

                STATE_BUTTERFLY_START:
                begin
                    /*
                     * butterfly_start is asserted for this clock.
                     */
                    state <= STATE_BUTTERFLY_WAIT;
                end

                STATE_BUTTERFLY_WAIT:
                begin
                    if (butterfly_done)
                    begin
                        state <= STATE_WRITEBACK;
                    end
                end

                STATE_WRITEBACK:
                begin
                    /*
                     * Both BRAM writes and schedule advancement occur
                     * on this edge.
                     */
                    butterfly_count <=
                        butterfly_count + 1'b1;

                    if (
                        current_operation_index
                        == 10'd1023
                    )
                    begin
                        busy <= 1'b0;
                        done <= 1'b1;

                        state <= STATE_IDLE;
                    end
                    else
                    begin
                        state <= STATE_READ_ISSUE;
                    end
                end

                default:
                begin
                    state <= STATE_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
