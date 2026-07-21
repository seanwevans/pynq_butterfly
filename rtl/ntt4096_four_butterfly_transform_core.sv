`timescale 1ns/1ps

/*
 * Four-butterfly N=4096 cyclic NTT transform checkpoint.
 *
 * Forward mode:
 *     descending DIF stages 11 through 0
 *
 * Inverse mode:
 *     ascending unscaled DIT stages 0 through 11
 *
 * Exact timing with the timing-isolated radix-4 butterfly:
 *
 *     schedule start:             1 cycle
 *     6144 groups * 23 cycles: 141312 cycles
 *                               -------------
 *     total:                   141313 cycles
 */
module ntt4096_four_butterfly_transform_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        modulus_we,
    input  logic [31:0] modulus_data,

    input  logic        twiddle_we,
    input  logic [11:0] twiddle_addr,
    input  logic [31:0] twiddle_data,

    input  logic        load_we,
    input  logic [11:0] load_addr,
    input  logic [31:0] load_data,

    input  logic [11:0] read_addr,
    output logic [31:0] read_data,

    input  logic        start,
    input  logic        inverse_mode,

    output logic        busy,
    output logic        done,
    output logic [31:0] cycles,
    output logic [14:0] butterfly_count
);

    localparam logic [8:0] LAST_GROUP =
        9'd511;

    localparam logic [14:0] TOTAL_BUTTERFLIES =
        15'd24576;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_SCHEDULE_START,
        STATE_READ_ISSUE,
        STATE_READ_CAPTURE_START,
        STATE_WAIT,
        STATE_WRITEBACK
    } state_t;

    state_t state;

    logic [31:0] modulus_register;
    logic        inverse_mode_register;

    logic [3:0] current_stage;
    logic [8:0] current_group;

    logic [7:0][11:0] schedule_address;

    ntt4096_four_butterfly_schedule_core schedule (
        .stage (
            current_stage
        ),

        .group_index (
            current_group
        ),

        .address (
            schedule_address
        )
    );

    logic [12:0] stage_one;
    logic [11:0] twiddle_mask;
    logic [12:0] twiddle_stage_base;

    logic [3:0][11:0] twiddle_read_address;
    logic [3:0][31:0] twiddle_read_data;
    logic             twiddle_read_enable;

    integer twiddle_lane;

    always_comb
    begin
        stage_one =
            13'd1 << current_stage;

        twiddle_mask =
            stage_one[11:0] - 1'b1;

        twiddle_stage_base =
            stage_one - 1'b1;

        for (
            twiddle_lane = 0;
            twiddle_lane < 4;
            twiddle_lane = twiddle_lane + 1
        )
        begin
            twiddle_read_address[twiddle_lane] =
                twiddle_stage_base[11:0]
                + (
                    schedule_address[
                        2 * twiddle_lane
                    ]
                    & twiddle_mask
                );
        end
    end

    assign twiddle_read_enable =
        state == STATE_READ_ISSUE;

    ntt4096_profile_bram_four_read twiddle_memory (
        .clk (
            clk
        ),

        .write_enable (
            twiddle_we
            && !busy
        ),

        .write_address (
            twiddle_addr
        ),

        .write_data (
            twiddle_data
        ),

        .read_enable (
            twiddle_read_enable
        ),

        .read_address (
            twiddle_read_address
        ),

        .read_data (
            twiddle_read_data
        )
    );

    logic [7:0][11:0] coefficient_read_address;
    logic [7:0][31:0] coefficient_read_data;
    logic             coefficient_read_valid;
    logic             coefficient_read_data_valid;

    logic             coefficient_write_valid;
    logic [7:0][31:0] coefficient_write_data;

    logic [7:0][11:0] inspect_address;

    always_comb
    begin
        inspect_address[0] =
            read_addr;

        inspect_address[1] =
            read_addr ^ 12'd1;

        inspect_address[2] =
            read_addr ^ 12'd2;

        inspect_address[3] =
            read_addr ^ 12'd3;

        inspect_address[4] =
            read_addr ^ 12'd4;

        inspect_address[5] =
            read_addr ^ 12'd5;

        inspect_address[6] =
            read_addr ^ 12'd6;

        inspect_address[7] =
            read_addr ^ 12'd7;

        if (busy)
        begin
            coefficient_read_address =
                schedule_address;

            coefficient_read_valid =
                state == STATE_READ_ISSUE;
        end
        else
        begin
            coefficient_read_address =
                inspect_address;

            coefficient_read_valid =
                1'b1;
        end
    end

    assign read_data =
        coefficient_read_data[0];

    ntt4096_eight_bank_coeff_store_runtime coefficient_store (
        .clk (
            clk
        ),

        .load_we (
            load_we
            && !busy
        ),

        .load_addr (
            load_addr
        ),

        .load_data (
            load_data
        ),

        .read_valid (
            coefficient_read_valid
        ),

        .read_addr (
            coefficient_read_address
        ),

        .read_data_valid (
            coefficient_read_data_valid
        ),

        .read_data (
            coefficient_read_data
        ),

        .write_valid (
            coefficient_write_valid
        ),

        .write_addr (
            schedule_address
        ),

        .write_data (
            coefficient_write_data
        )
    );

    logic butterfly_start;

    logic [3:0] butterfly_busy;
    logic [3:0] butterfly_done;

    logic [3:0][31:0] butterfly_out_a;
    logic [3:0][31:0] butterfly_out_b;

    assign butterfly_start =
        state == STATE_READ_CAPTURE_START;

    generate
        genvar butterfly_index;

        for (
            butterfly_index = 0;
            butterfly_index < 4;
            butterfly_index = butterfly_index + 1
        )
        begin : butterflies
            ntt4096_dual_mode_butterfly_core butterfly (
                .clk (
                    clk
                ),

                .reset_n (
                    reset_n
                ),

                .start (
                    butterfly_start
                ),

                .inverse_mode (
                    inverse_mode_register
                ),

                .a (
                    coefficient_read_data[
                        2 * butterfly_index
                    ]
                ),

                .b (
                    coefficient_read_data[
                        2 * butterfly_index + 1
                    ]
                ),

                .omega (
                    twiddle_read_data[
                        butterfly_index
                    ]
                ),

                .q (
                    modulus_register
                ),

                .out_a (
                    butterfly_out_a[
                        butterfly_index
                    ]
                ),

                .out_b (
                    butterfly_out_b[
                        butterfly_index
                    ]
                ),

                .busy (
                    butterfly_busy[
                        butterfly_index
                    ]
                ),

                .done (
                    butterfly_done[
                        butterfly_index
                    ]
                )
            );

            assign coefficient_write_data[
                2 * butterfly_index
            ] =
                butterfly_out_a[
                    butterfly_index
                ];

            assign coefficient_write_data[
                2 * butterfly_index + 1
            ] =
                butterfly_out_b[
                    butterfly_index
                ];
        end
    endgenerate

    assign coefficient_write_valid =
        state == STATE_WRITEBACK;

    wire all_butterflies_done =
        &butterfly_done;

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

            current_stage <=
                4'd0;

            current_group <=
                9'd0;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

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
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start)
                    begin
                        inverse_mode_register <=
                            inverse_mode;

                        current_stage <=
                            inverse_mode
                                ? 4'd0
                                : 4'd11;

                        current_group <=
                            9'd0;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        butterfly_count <=
                            15'd0;

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
                        STATE_READ_CAPTURE_START;
                end

                STATE_READ_CAPTURE_START:
                begin
                    state <=
                        STATE_WAIT;
                end

                STATE_WAIT:
                begin
                    if (all_butterflies_done)
                    begin
                        state <=
                            STATE_WRITEBACK;
                    end
                end

                STATE_WRITEBACK:
                begin
                    butterfly_count <=
                        butterfly_count + 3'd4;

                    if (current_group == LAST_GROUP)
                    begin
                        current_group <=
                            9'd0;

                        if (
                            (
                                !inverse_mode_register
                                && current_stage == 4'd0
                            )
                            || (
                                inverse_mode_register
                                && current_stage == 4'd11
                            )
                        )
                        begin
                            butterfly_count <=
                                TOTAL_BUTTERFLIES;

                            busy <=
                                1'b0;

                            done <=
                                1'b1;

                            state <=
                                STATE_IDLE;
                        end
                        else if (inverse_mode_register)
                        begin
                            current_stage <=
                                current_stage + 1'b1;

                            state <=
                                STATE_READ_ISSUE;
                        end
                        else
                        begin
                            current_stage <=
                                current_stage - 1'b1;

                            state <=
                                STATE_READ_ISSUE;
                        end
                    end
                    else
                    begin
                        current_group <=
                            current_group + 1'b1;

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
                "ERROR: four-butterfly transform start while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_READ_CAPTURE_START
            && !coefficient_read_data_valid
        )
        begin
            $display(
                "ERROR: coefficient data invalid at butterfly launch"
            );

            $fatal(1);
        end

        if (
            (
                modulus_we
                || twiddle_we
                || load_we
            )
            && busy
        )
        begin
            $display(
                "ERROR: runtime load attempted while transform busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
