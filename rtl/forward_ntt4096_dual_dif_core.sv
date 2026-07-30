`timescale 1ns/1ps

/*
 * Two-bank N=4096 forward negacyclic NTT.
 *
 * The two polynomials execute in lockstep while sharing:
 *
 *     one coefficient index
 *     one twist-factor ROM
 *     one DIF scheduler
 *     one forward-twiddle ROM
 *
 * Arithmetic remains two-lane:
 *
 *     two preprocessing modmul_core instances
 *     two butterfly_dif_core instances
 *
 * Each polynomial owns only one 4096 x 32-bit coefficient BRAM.
 *
 * Processing:
 *
 *     natural coefficients
 *         -> in-place multiplication by psi^j
 *         -> in-place forward DIF cyclic NTT
 *         -> bit-reversed evaluation-domain coefficients
 *
 * For natural transform index k:
 *
 *     memory[bit_reverse(k)] = forward_ntt[k]
 */
module forward_ntt4096_dual_dif_core #(
    parameter TWIST_INIT_FILE =
        "../tests/fixtures/ntt_n4096/twist_factors.mem",

    parameter TWIDDLE_INIT_FILE =
        "../tests/fixtures/ntt_n4096/forward_twiddles.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_a_we,
    input  logic [11:0] load_a_addr,
    input  logic [31:0] load_a_data,

    input  logic        load_b_we,
    input  logic [11:0] load_b_addr,
    input  logic [31:0] load_b_data,

    input  logic [11:0] read_a_addr,
    output logic [31:0] read_a_data,

    input  logic [11:0] read_b_addr,
    output logic [31:0] read_b_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [12:0] preprocessing_count,
    output logic [14:0] butterfly_count
);

    localparam logic [31:0] MODULUS =
        ntt4096_profile_pkg::NTT_Q;

    localparam integer TOTAL_COEFFICIENTS =
        4096;

    localparam integer TOTAL_BUTTERFLIES =
        24576;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PREP_READ_ISSUE,
        STATE_PREP_READ_CAPTURE,
        STATE_PREP_MUL_START,
        STATE_PREP_MUL_WAIT,
        STATE_PREP_WRITEBACK,
        STATE_DIF_SCHEDULE_START,
        STATE_DIF_READ_ISSUE,
        STATE_DIF_READ_CAPTURE,
        STATE_DIF_BUTTERFLY_START,
        STATE_DIF_BUTTERFLY_WAIT,
        STATE_DIF_WRITEBACK
    } state_t;

    state_t state;

    logic [11:0] coefficient_index;

    logic twist_enable;
    logic [31:0] twist_read_data;

    logic prep_start;

    logic prep_a_busy;
    logic prep_a_done;
    logic [31:0] prep_a_result;

    logic prep_b_busy;
    logic prep_b_done;
    logic [31:0] prep_b_result;

    logic [31:0] captured_prep_a;
    logic [31:0] captured_prep_b;
    logic [31:0] captured_twist;

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

    logic dif_start;

    logic dif_a_busy;
    logic dif_a_done;
    logic [31:0] dif_a_out_left;
    logic [31:0] dif_a_out_right;

    logic dif_b_busy;
    logic dif_b_done;
    logic [31:0] dif_b_out_left;
    logic [31:0] dif_b_out_right;

    logic [31:0] captured_a_left;
    logic [31:0] captured_a_right;

    logic [31:0] captured_b_left;
    logic [31:0] captured_b_right;

    logic [31:0] captured_twiddle;

    logic        bank_a_port_a_enable;
    logic        bank_a_port_a_write_enable;
    logic [11:0] bank_a_port_a_address;
    logic [31:0] bank_a_port_a_write_data;
    logic [31:0] bank_a_port_a_read_data;

    logic        bank_a_port_b_enable;
    logic        bank_a_port_b_write_enable;
    logic [11:0] bank_a_port_b_address;
    logic [31:0] bank_a_port_b_write_data;
    logic [31:0] bank_a_port_b_read_data;

    logic        bank_b_port_a_enable;
    logic        bank_b_port_a_write_enable;
    logic [11:0] bank_b_port_a_address;
    logic [31:0] bank_b_port_a_write_data;
    logic [31:0] bank_b_port_a_read_data;

    logic        bank_b_port_b_enable;
    logic        bank_b_port_b_write_enable;
    logic [11:0] bank_b_port_b_address;
    logic [31:0] bank_b_port_b_write_data;
    logic [31:0] bank_b_port_b_read_data;

    assign twist_enable =
        state == STATE_PREP_READ_ISSUE;

    assign prep_start =
        state == STATE_PREP_MUL_START;

    assign schedule_start =
        state == STATE_DIF_SCHEDULE_START;

    assign schedule_advance =
        state == STATE_DIF_WRITEBACK;

    assign twiddle_enable =
        state == STATE_DIF_READ_ISSUE;

    assign dif_start =
        state == STATE_DIF_BUTTERFLY_START;

    assign read_a_data =
        bank_a_port_a_read_data;

    assign read_b_data =
        bank_b_port_a_read_data;

    always_comb
    begin
        bank_a_port_a_enable =
            1'b0;

        bank_a_port_a_write_enable =
            1'b0;

        bank_a_port_a_address =
            12'd0;

        bank_a_port_a_write_data =
            32'd0;

        bank_a_port_b_enable =
            1'b0;

        bank_a_port_b_write_enable =
            1'b0;

        bank_a_port_b_address =
            12'd0;

        bank_a_port_b_write_data =
            32'd0;

        if (!busy)
        begin
            bank_a_port_a_enable =
                1'b1;

            bank_a_port_a_write_enable =
                load_a_we;

            bank_a_port_a_address =
                load_a_we
                    ? load_a_addr
                    : read_a_addr;

            bank_a_port_a_write_data =
                load_a_data;
        end
        else
        begin
            case (state)
                STATE_PREP_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;
                end

                STATE_PREP_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;

                    bank_a_port_a_write_data =
                        prep_a_result;
                end

                STATE_DIF_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        schedule_left_addr;

                    bank_a_port_b_enable =
                        1'b1;

                    bank_a_port_b_address =
                        schedule_right_addr;
                end

                STATE_DIF_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        schedule_left_addr;

                    bank_a_port_a_write_data =
                        dif_a_out_left;

                    bank_a_port_b_enable =
                        1'b1;

                    bank_a_port_b_write_enable =
                        1'b1;

                    bank_a_port_b_address =
                        schedule_right_addr;

                    bank_a_port_b_write_data =
                        dif_a_out_right;
                end

                default:
                begin
                end
            endcase
        end
    end

    always_comb
    begin
        bank_b_port_a_enable =
            1'b0;

        bank_b_port_a_write_enable =
            1'b0;

        bank_b_port_a_address =
            12'd0;

        bank_b_port_a_write_data =
            32'd0;

        bank_b_port_b_enable =
            1'b0;

        bank_b_port_b_write_enable =
            1'b0;

        bank_b_port_b_address =
            12'd0;

        bank_b_port_b_write_data =
            32'd0;

        if (!busy)
        begin
            bank_b_port_a_enable =
                1'b1;

            bank_b_port_a_write_enable =
                load_b_we;

            bank_b_port_a_address =
                load_b_we
                    ? load_b_addr
                    : read_b_addr;

            bank_b_port_a_write_data =
                load_b_data;
        end
        else
        begin
            case (state)
                STATE_PREP_READ_ISSUE:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_address =
                        coefficient_index;
                end

                STATE_PREP_WRITEBACK:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_write_enable =
                        1'b1;

                    bank_b_port_a_address =
                        coefficient_index;

                    bank_b_port_a_write_data =
                        prep_b_result;
                end

                STATE_DIF_READ_ISSUE:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_address =
                        schedule_left_addr;

                    bank_b_port_b_enable =
                        1'b1;

                    bank_b_port_b_address =
                        schedule_right_addr;
                end

                STATE_DIF_WRITEBACK:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_write_enable =
                        1'b1;

                    bank_b_port_a_address =
                        schedule_left_addr;

                    bank_b_port_a_write_data =
                        dif_b_out_left;

                    bank_b_port_b_enable =
                        1'b1;

                    bank_b_port_b_write_enable =
                        1'b1;

                    bank_b_port_b_address =
                        schedule_right_addr;

                    bank_b_port_b_write_data =
                        dif_b_out_right;
                end

                default:
                begin
                end
            endcase
        end
    end

    ntt4096_coeff_bram coefficient_bank_a (
        .clk                 (clk),

        .port_a_enable       (bank_a_port_a_enable),
        .port_a_write_enable (bank_a_port_a_write_enable),
        .port_a_address      (bank_a_port_a_address),
        .port_a_write_data   (bank_a_port_a_write_data),
        .port_a_read_data    (bank_a_port_a_read_data),

        .port_b_enable       (bank_a_port_b_enable),
        .port_b_write_enable (bank_a_port_b_write_enable),
        .port_b_address      (bank_a_port_b_address),
        .port_b_write_data   (bank_a_port_b_write_data),
        .port_b_read_data    (bank_a_port_b_read_data)
    );

    ntt4096_coeff_bram coefficient_bank_b (
        .clk                 (clk),

        .port_a_enable       (bank_b_port_a_enable),
        .port_a_write_enable (bank_b_port_a_write_enable),
        .port_a_address      (bank_b_port_a_address),
        .port_a_write_data   (bank_b_port_a_write_data),
        .port_a_read_data    (bank_b_port_a_read_data),

        .port_b_enable       (bank_b_port_b_enable),
        .port_b_write_enable (bank_b_port_b_write_enable),
        .port_b_address      (bank_b_port_b_address),
        .port_b_write_data   (bank_b_port_b_write_data),
        .port_b_read_data    (bank_b_port_b_read_data)
    );

    ntt4096_factor_rom #(
        .INIT_FILE(
            TWIST_INIT_FILE
        )
    ) shared_twist_rom (
        .clk       (clk),
        .enable    (twist_enable),
        .address   (coefficient_index),
        .read_data (twist_read_data)
    );

    modmul_core preprocessing_lane_a (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (prep_start),

        .a       (captured_prep_a),
        .b       (captured_twist),
        .q       (MODULUS),

        .result  (prep_a_result),
        .busy    (prep_a_busy),
        .done    (prep_a_done)
    );

    modmul_core preprocessing_lane_b (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (prep_start),

        .a       (captured_prep_b),
        .b       (captured_twist),
        .q       (MODULUS),

        .result  (prep_b_result),
        .busy    (prep_b_busy),
        .done    (prep_b_done)
    );

    ntt4096_dif_schedule_core shared_schedule (
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
    ) shared_twiddle_rom (
        .clk       (clk),
        .enable    (twiddle_enable),
        .address   (schedule_twiddle_addr),
        .read_data (twiddle_read_data)
    );

    butterfly_dif_core butterfly_lane_a (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (dif_start),

        .a       (captured_a_left),
        .b       (captured_a_right),
        .omega   (captured_twiddle),
        .q       (MODULUS),

        .out_a   (dif_a_out_left),
        .out_b   (dif_a_out_right),
        .busy    (dif_a_busy),
        .done    (dif_a_done)
    );

    butterfly_dif_core butterfly_lane_b (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (dif_start),

        .a       (captured_b_left),
        .b       (captured_b_right),
        .omega   (captured_twiddle),
        .q       (MODULUS),

        .out_a   (dif_b_out_left),
        .out_b   (dif_b_out_right),
        .busy    (dif_b_busy),
        .done    (dif_b_done)
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

            coefficient_index <=
                12'd0;

            preprocessing_count <=
                13'd0;

            butterfly_count <=
                15'd0;

            captured_prep_a <=
                32'd0;

            captured_prep_b <=
                32'd0;

            captured_twist <=
                32'd0;

            captured_a_left <=
                32'd0;

            captured_a_right <=
                32'd0;

            captured_b_left <=
                32'd0;

            captured_b_right <=
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
                            STATE_PREP_READ_ISSUE;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        coefficient_index <=
                            12'd0;

                        preprocessing_count <=
                            13'd0;

                        butterfly_count <=
                            15'd0;
                    end
                end

                STATE_PREP_READ_ISSUE:
                begin
                    state <=
                        STATE_PREP_READ_CAPTURE;
                end

                STATE_PREP_READ_CAPTURE:
                begin
                    captured_prep_a <=
                        bank_a_port_a_read_data;

                    captured_prep_b <=
                        bank_b_port_a_read_data;

                    captured_twist <=
                        twist_read_data;

                    state <=
                        STATE_PREP_MUL_START;
                end

                STATE_PREP_MUL_START:
                begin
                    state <=
                        STATE_PREP_MUL_WAIT;
                end

                STATE_PREP_MUL_WAIT:
                begin
                    if (
                        prep_a_done
                        && prep_b_done
                    )
                    begin
                        state <=
                            STATE_PREP_WRITEBACK;
                    end
                end

                STATE_PREP_WRITEBACK:
                begin
                    preprocessing_count <=
                        preprocessing_count + 1'b1;

                    if (
                        coefficient_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_DIF_SCHEDULE_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;

                        state <=
                            STATE_PREP_READ_ISSUE;
                    end
                end

                STATE_DIF_SCHEDULE_START:
                begin
                    state <=
                        STATE_DIF_READ_ISSUE;
                end

                STATE_DIF_READ_ISSUE:
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
                            STATE_DIF_READ_CAPTURE;
                    end
                end

                STATE_DIF_READ_CAPTURE:
                begin
                    captured_a_left <=
                        bank_a_port_a_read_data;

                    captured_a_right <=
                        bank_a_port_b_read_data;

                    captured_b_left <=
                        bank_b_port_a_read_data;

                    captured_b_right <=
                        bank_b_port_b_read_data;

                    captured_twiddle <=
                        twiddle_read_data;

                    state <=
                        STATE_DIF_BUTTERFLY_START;
                end

                STATE_DIF_BUTTERFLY_START:
                begin
                    state <=
                        STATE_DIF_BUTTERFLY_WAIT;
                end

                STATE_DIF_BUTTERFLY_WAIT:
                begin
                    if (
                        dif_a_done
                        && dif_b_done
                    )
                    begin
                        state <=
                            STATE_DIF_WRITEBACK;
                    end
                end

                STATE_DIF_WRITEBACK:
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
                            STATE_DIF_READ_ISSUE;
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
            prep_a_done
            ^ prep_b_done
        )
        begin
            $display(
                "ERROR: dual preprocessing lanes completed on different clocks"
            );

            $fatal(1);
        end

        if (
            dif_a_done
            ^ dif_b_done
        )
        begin
            $display(
                "ERROR: dual DIF butterfly lanes completed on different clocks"
            );

            $fatal(1);
        end

        if (
            state == STATE_PREP_MUL_START
            && (
                prep_a_busy
                || prep_b_busy
            )
        )
        begin
            $display(
                "ERROR: dual preprocessing start attempted while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_DIF_BUTTERFLY_START
            && (
                dif_a_busy
                || dif_b_busy
            )
        )
        begin
            $display(
                "ERROR: dual DIF start attempted while busy"
            );

            $fatal(1);
        end

        if (
            busy
            && state >= STATE_DIF_READ_ISSUE
            && state != STATE_DIF_WRITEBACK
            && (
                !schedule_busy
                || !schedule_valid
            )
        )
        begin
            $display(
                "ERROR: shared DIF schedule invalid state=%0d operation=%0d",
                state,
                schedule_operation
            );

            $fatal(1);
        end
    end

`endif

endmodule
