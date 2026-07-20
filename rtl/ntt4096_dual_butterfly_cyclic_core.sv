`timescale 1ns/1ps

/*
 * Runtime-profile N=4096 cyclic NTT engine with two concurrent
 * butterfly datapaths.
 *
 * Forward mode:
 *
 *     inverse_mode=0
 *     natural-order input
 *     descending DIF stages
 *     bit-reversed physical output
 *
 * Inverse mode:
 *
 *     inverse_mode=1
 *     bit-reversed physical input
 *     ascending DIT stages
 *     natural-order unscaled output
 *
 * The inverse result is N times the original coefficient vector. The
 * existing polynomial multiplier performs N^-1 scaling in its separate
 * postprocessing phase.
 */
module ntt4096_dual_butterfly_cyclic_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,
    input  logic        inverse_mode,

    input  logic        modulus_we,
    input  logic [31:0] modulus_data,

    input  logic        profile_we,
    input  logic [11:0] profile_addr,
    input  logic [31:0] profile_data,
    input  logic        profile_commit,

    output logic        profile_ready,
    output logic [31:0] active_modulus,

    input  logic        load_we,
    input  logic [11:0] load_addr,
    input  logic [31:0] load_data,

    input  logic        inspect_valid,
    input  logic [11:0] inspect_addr0,
    input  logic [11:0] inspect_addr1,
    input  logic [11:0] inspect_addr2,
    input  logic [11:0] inspect_addr3,

    output logic        inspect_data_valid,
    output logic [31:0] inspect_data0,
    output logic [31:0] inspect_data1,
    output logic [31:0] inspect_data2,
    output logic [31:0] inspect_data3,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [13:0] pair_count,
    output logic [14:0] butterfly_count
);

    localparam logic [13:0] TOTAL_PAIRS =
        14'd12288;

    localparam logic [14:0] TOTAL_BUTTERFLIES =
        15'd24576;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_SCHEDULE_START,
        STATE_READ_ISSUE,
        STATE_READ_CAPTURE,
        STATE_BUTTERFLY_WAIT,
        STATE_WRITEBACK
    } state_t;

    state_t state;

    logic [31:0] modulus_register;
    logic        inverse_mode_register;

    logic schedule_start;
    logic schedule_advance;
    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;

    logic [3:0] schedule_stage;
    logic [9:0] schedule_pair;

    logic [11:0] schedule_address0_a;
    logic [11:0] schedule_address0_b;
    logic [11:0] schedule_address1_a;
    logic [11:0] schedule_address1_b;

    logic [11:0] schedule_twiddle_address0;
    logic [11:0] schedule_twiddle_address1;

    logic store_read_valid;
    logic [11:0] store_read_addr0;
    logic [11:0] store_read_addr1;
    logic [11:0] store_read_addr2;
    logic [11:0] store_read_addr3;

    logic store_read_data_valid;
    logic [31:0] store_read_data0;
    logic [31:0] store_read_data1;
    logic [31:0] store_read_data2;
    logic [31:0] store_read_data3;

    logic store_write_valid;

    logic profile_read_enable;
    logic [31:0] profile_read_data0;
    logic [31:0] profile_read_data1;

    logic butterfly_start;

    logic butterfly0_busy;
    logic butterfly0_done;
    logic [31:0] butterfly0_out_a;
    logic [31:0] butterfly0_out_b;

    logic butterfly1_busy;
    logic butterfly1_done;
    logic [31:0] butterfly1_out_a;
    logic [31:0] butterfly1_out_b;

    assign active_modulus =
        modulus_register;

    assign schedule_start =
        state == STATE_SCHEDULE_START;

    assign schedule_advance =
        state == STATE_WRITEBACK;

    assign profile_read_enable =
        state == STATE_READ_ISSUE;

    /*
     * BRAM outputs are valid throughout STATE_READ_CAPTURE. Launching
     * both butterflies directly in that state removes one controller
     * bubble for every one of the 12,288 paired entries.
     */
    assign butterfly_start =
        state == STATE_READ_CAPTURE;

    assign store_write_valid =
        state == STATE_WRITEBACK;

    assign store_read_valid =
        busy
            ? state == STATE_READ_ISSUE
            : inspect_valid;

    assign store_read_addr0 =
        busy
            ? schedule_address0_a
            : inspect_addr0;

    assign store_read_addr1 =
        busy
            ? schedule_address0_b
            : inspect_addr1;

    assign store_read_addr2 =
        busy
            ? schedule_address1_a
            : inspect_addr2;

    assign store_read_addr3 =
        busy
            ? schedule_address1_b
            : inspect_addr3;

    assign inspect_data_valid =
        !busy
        && store_read_data_valid;

    assign inspect_data0 =
        store_read_data0;

    assign inspect_data1 =
        store_read_data1;

    assign inspect_data2 =
        store_read_data2;

    assign inspect_data3 =
        store_read_data3;

    ntt4096_paired_schedule_core schedule (
        .clk               (clk),
        .reset_n           (reset_n),

        .start             (schedule_start),
        .descending        (!inverse_mode_register),
        .advance           (schedule_advance),

        .busy              (schedule_busy),
        .valid             (schedule_valid),
        .done              (schedule_done),

        .stage_bit         (schedule_stage),
        .pair_index        (schedule_pair),

        .address0_a        (schedule_address0_a),
        .address0_b        (schedule_address0_b),
        .address1_a        (schedule_address1_a),
        .address1_b        (schedule_address1_b),

        .twiddle_address0  (schedule_twiddle_address0),
        .twiddle_address1  (schedule_twiddle_address1)
    );

    ntt4096_profile_bram_dual_read profile_memory (
        .clk            (clk),

        .write_enable   (profile_we && !busy),
        .write_address  (profile_addr),
        .write_data     (profile_data),

        .read_enable_a  (profile_read_enable),
        .read_address_a (schedule_twiddle_address0),
        .read_data_a    (profile_read_data0),

        .read_enable_b  (profile_read_enable),
        .read_address_b (schedule_twiddle_address1),
        .read_data_b    (profile_read_data1)
    );

    ntt4096_four_bank_coeff_store coefficient_memory (
        .clk             (clk),
        .reset_n         (reset_n),

        .load_we         (load_we && !busy),
        .load_addr       (load_addr),
        .load_data       (load_data),

        .read_valid      (store_read_valid),
        .read_addr0      (store_read_addr0),
        .read_addr1      (store_read_addr1),
        .read_addr2      (store_read_addr2),
        .read_addr3      (store_read_addr3),

        .read_data_valid (store_read_data_valid),
        .read_data0      (store_read_data0),
        .read_data1      (store_read_data1),
        .read_data2      (store_read_data2),
        .read_data3      (store_read_data3),

        .write_valid     (store_write_valid),
        .write_addr0     (schedule_address0_a),
        .write_addr1     (schedule_address0_b),
        .write_addr2     (schedule_address1_a),
        .write_addr3     (schedule_address1_b),
        .write_data0     (butterfly0_out_a),
        .write_data1     (butterfly0_out_b),
        .write_data2     (butterfly1_out_a),
        .write_data3     (butterfly1_out_b)
    );

    ntt4096_dual_mode_butterfly_core butterfly0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (butterfly_start),

        .inverse_mode (inverse_mode_register),
        .a            (store_read_data0),
        .b            (store_read_data1),
        .omega        (profile_read_data0),
        .q            (modulus_register),

        .out_a        (butterfly0_out_a),
        .out_b        (butterfly0_out_b),
        .busy         (butterfly0_busy),
        .done         (butterfly0_done)
    );

    ntt4096_dual_mode_butterfly_core butterfly1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (butterfly_start),

        .inverse_mode (inverse_mode_register),
        .a            (store_read_data2),
        .b            (store_read_data3),
        .omega        (profile_read_data1),
        .q            (modulus_register),

        .out_a        (butterfly1_out_a),
        .out_b        (butterfly1_out_b),
        .busy         (butterfly1_busy),
        .done         (butterfly1_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            modulus_register <=
                32'd0;

            inverse_mode_register <=
                1'b0;

            profile_ready <=
                1'b0;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            pair_count <=
                14'd0;

            butterfly_count <=
                15'd0;

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

            if (!busy && modulus_we)
            begin
                modulus_register <=
                    modulus_data;

                profile_ready <=
                    1'b0;
            end

            if (!busy && profile_we)
            begin
                profile_ready <=
                    1'b0;
            end

            if (!busy && profile_commit)
            begin
                profile_ready <=
                    1'b1;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && profile_ready)
                    begin
                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        pair_count <=
                            14'd0;

                        butterfly_count <=
                            15'd0;

                        inverse_mode_register <=
                            inverse_mode;

                        state <=
                            STATE_SCHEDULE_START;
                    end
                end

                STATE_SCHEDULE_START:
                begin
                    state <=
                        STATE_READ_ISSUE;
                end

                STATE_READ_ISSUE:
                begin
                    state <=
                        STATE_READ_CAPTURE;
                end

                STATE_READ_CAPTURE:
                begin
                    /*
                     * The two butterflies sample the synchronous BRAM
                     * outputs on this edge. No separate launch state is
                     * needed.
                     */
                    state <=
                        STATE_BUTTERFLY_WAIT;
                end

                STATE_BUTTERFLY_WAIT:
                begin
                    if (butterfly0_done && butterfly1_done)
                    begin
                        state <=
                            STATE_WRITEBACK;
                    end
                end

                STATE_WRITEBACK:
                begin
                    pair_count <=
                        pair_count + 1'b1;

                    butterfly_count <=
                        butterfly_count + 2'd2;

                    if (pair_count == TOTAL_PAIRS - 1'b1)
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
        if (start && busy)
        begin
            $display(
                "ERROR: dual-butterfly transform start attempted while busy"
            );

            $fatal(1);
        end

        if (start && !profile_ready)
        begin
            $display(
                "ERROR: dual-butterfly transform started without committed profile"
            );

            $fatal(1);
        end

        if (
            state == STATE_READ_CAPTURE
            && !store_read_data_valid
        )
        begin
            $display(
                "ERROR: coefficient read data was not valid at capture"
            );

            $fatal(1);
        end

        if (butterfly0_done != butterfly1_done)
        begin
            $display(
                "ERROR: paired butterfly lanes left lockstep"
            );

            $fatal(1);
        end

        if (
            done
            && (
                pair_count != TOTAL_PAIRS
                || butterfly_count != TOTAL_BUTTERFLIES
            )
        )
        begin
            $display(
                "ERROR: completed transform reported wrong operation counts"
            );

            $fatal(1);
        end
    end

`endif

endmodule
