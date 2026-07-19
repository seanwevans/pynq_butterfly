`timescale 1ns/1ps

/*
 * Complete N=4096 radix-2 DIT cyclic NTT controller.
 *
 * Input coefficients must already be in bit-reversed order. The output
 * is left in natural order.
 *
 * One butterfly is processed at a time through the existing
 * butterfly_core. The schedule entry remains fixed until both
 * coefficient results are written back.
 *
 * Idle-time memory interface:
 *
 *     load_we=1 writes load_data to load_addr
 *     load_we=0 synchronously reads read_addr
 *
 * The external memory interface is ignored while busy.
 */
module ntt4096_cyclic_core #(
    parameter TWIDDLE_INIT_FILE =
        "../model/golden_n4096/forward_twiddles.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_we,
    input  logic [11:0] load_addr,
    input  logic [31:0] load_data,

    input  logic [11:0] read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [14:0] butterfly_count
);

    import ntt4096_profile_pkg::*;

    localparam logic [31:0] MODULUS =
        ntt4096_profile_pkg::NTT_Q;

    localparam integer TOTAL_BUTTERFLIES =
        ntt4096_profile_pkg::NTT_BUTTERFLIES_PER_TRANSFORM;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_SCHEDULE_START,
        STATE_READ_ISSUE,
        STATE_READ_CAPTURE,
        STATE_BUTTERFLY_START,
        STATE_BUTTERFLY_WAIT,
        STATE_WRITEBACK
    } state_t;

    state_t state;

    logic schedule_start;
    logic schedule_advance;

    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;

    logic [14:0] schedule_operation;
    logic [3:0]  schedule_stage;
    logic [11:0] schedule_group;
    logic [11:0] schedule_j;

    logic [11:0] schedule_left_addr;
    logic [11:0] schedule_right_addr;
    logic [11:0] schedule_twiddle_addr;

    logic twiddle_enable;
    logic [31:0] twiddle_read_data;

    logic        bram_port_a_enable;
    logic        bram_port_a_write_enable;
    logic [11:0] bram_port_a_address;
    logic [31:0] bram_port_a_write_data;
    logic [31:0] bram_port_a_read_data;

    logic        bram_port_b_enable;
    logic        bram_port_b_write_enable;
    logic [11:0] bram_port_b_address;
    logic [31:0] bram_port_b_write_data;
    logic [31:0] bram_port_b_read_data;

    logic [31:0] captured_left;
    logic [31:0] captured_right;
    logic [31:0] captured_twiddle;

    logic butterfly_start;
    logic butterfly_busy;
    logic butterfly_done;

    logic [31:0] butterfly_out_left;
    logic [31:0] butterfly_out_right;

    assign schedule_start =
        state == STATE_SCHEDULE_START;

    assign schedule_advance =
        state == STATE_WRITEBACK;

    assign butterfly_start =
        state == STATE_BUTTERFLY_START;

    assign twiddle_enable =
        state == STATE_READ_ISSUE;

    assign read_data =
        bram_port_a_read_data;

    /*
     * Coefficient-memory port mux.
     *
     * Idle:
     *   port A implements external load/read access
     *
     * Busy READ_ISSUE:
     *   ports A and B issue the two butterfly coefficient reads
     *
     * Busy WRITEBACK:
     *   ports A and B write both butterfly outputs simultaneously
     */
    always_comb
    begin
        bram_port_a_enable =
            1'b0;

        bram_port_a_write_enable =
            1'b0;

        bram_port_a_address =
            12'd0;

        bram_port_a_write_data =
            32'd0;

        bram_port_b_enable =
            1'b0;

        bram_port_b_write_enable =
            1'b0;

        bram_port_b_address =
            12'd0;

        bram_port_b_write_data =
            32'd0;

        if (!busy)
        begin
            bram_port_a_enable =
                1'b1;

            bram_port_a_write_enable =
                load_we;

            bram_port_a_address =
                load_we
                    ? load_addr
                    : read_addr;

            bram_port_a_write_data =
                load_data;
        end
        else
        begin
            case (state)
                STATE_READ_ISSUE:
                begin
                    bram_port_a_enable =
                        1'b1;

                    bram_port_a_address =
                        schedule_left_addr;

                    bram_port_b_enable =
                        1'b1;

                    bram_port_b_address =
                        schedule_right_addr;
                end

                STATE_WRITEBACK:
                begin
                    bram_port_a_enable =
                        1'b1;

                    bram_port_a_write_enable =
                        1'b1;

                    bram_port_a_address =
                        schedule_left_addr;

                    bram_port_a_write_data =
                        butterfly_out_left;

                    bram_port_b_enable =
                        1'b1;

                    bram_port_b_write_enable =
                        1'b1;

                    bram_port_b_address =
                        schedule_right_addr;

                    bram_port_b_write_data =
                        butterfly_out_right;
                end

                default:
                begin
                end
            endcase
        end
    end

    ntt4096_schedule_core schedule (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (schedule_start),
        .advance      (schedule_advance),

        .busy         (schedule_busy),
        .valid        (schedule_valid),
        .done         (schedule_done),

        .operation    (schedule_operation),
        .stage        (schedule_stage),
        .group        (schedule_group),
        .j            (schedule_j),

        .left_addr    (schedule_left_addr),
        .right_addr   (schedule_right_addr),
        .twiddle_addr (schedule_twiddle_addr)
    );

    ntt4096_twiddle_rom #(
        .INIT_FILE(
            TWIDDLE_INIT_FILE
        )
    ) twiddle_rom (
        .clk       (clk),
        .enable    (twiddle_enable),
        .address   (schedule_twiddle_addr),
        .read_data (twiddle_read_data)
    );

    ntt4096_coeff_bram coefficient_memory (
        .clk                 (clk),

        .port_a_enable       (bram_port_a_enable),
        .port_a_write_enable (bram_port_a_write_enable),
        .port_a_address      (bram_port_a_address),
        .port_a_write_data   (bram_port_a_write_data),
        .port_a_read_data    (bram_port_a_read_data),

        .port_b_enable       (bram_port_b_enable),
        .port_b_write_enable (bram_port_b_write_enable),
        .port_b_address      (bram_port_b_address),
        .port_b_write_data   (bram_port_b_write_data),
        .port_b_read_data    (bram_port_b_read_data)
    );

    butterfly_core butterfly (
        .clk    (clk),
        .reset_n(reset_n),
        .start  (butterfly_start),

        .a      (captured_left),
        .b      (captured_right),
        .omega  (captured_twiddle),
        .q      (MODULUS),

        .out_a  (butterfly_out_left),
        .out_b  (butterfly_out_right),
        .busy   (butterfly_busy),
        .done   (butterfly_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            butterfly_count <=
                15'd0;

            captured_left <=
                32'd0;

            captured_right <=
                32'd0;

            captured_twiddle <=
                32'd0;
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
                        state <=
                            STATE_SCHEDULE_START;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        butterfly_count <=
                            15'd0;
                    end
                end

                STATE_SCHEDULE_START:
                begin
                    state <=
                        STATE_READ_ISSUE;
                end

                STATE_READ_ISSUE:
                begin
                    if (
                        !schedule_busy
                        || !schedule_valid
                    )
                    begin
                        state <=
                            STATE_IDLE;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                    else
                    begin
                        state <=
                            STATE_READ_CAPTURE;
                    end
                end

                STATE_READ_CAPTURE:
                begin
                    captured_left <=
                        bram_port_a_read_data;

                    captured_right <=
                        bram_port_b_read_data;

                    captured_twiddle <=
                        twiddle_read_data;

                    state <=
                        STATE_BUTTERFLY_START;
                end

                STATE_BUTTERFLY_START:
                begin
                    state <=
                        STATE_BUTTERFLY_WAIT;
                end

                STATE_BUTTERFLY_WAIT:
                begin
                    if (butterfly_done)
                    begin
                        state <=
                            STATE_WRITEBACK;
                    end
                end

                STATE_WRITEBACK:
                begin
                    butterfly_count <=
                        butterfly_count + 1'b1;

                    if (
                        butterfly_count
                        == TOTAL_BUTTERFLIES - 1
                    )
                    begin
                        state <=
                            STATE_IDLE;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                    else
                    begin
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

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            busy
            && state != STATE_SCHEDULE_START
            && (
                !schedule_busy
                || !schedule_valid
            )
            && state != STATE_WRITEBACK
        )
        begin
            $display(
                "ERROR: N=4096 scheduler became invalid during transform state=%0d operation=%0d",
                state,
                schedule_operation
            );

            $fatal(1);
        end

        if (
            state == STATE_BUTTERFLY_START
            && butterfly_busy
        )
        begin
            $display(
                "ERROR: N=4096 butterfly start attempted while busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
