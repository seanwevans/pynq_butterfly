`timescale 1ns/1ps

/*
 * External-memory four-lane N=4096 cyclic NTT engine.
 *
 * Forward mode:
 *     descending DIF stages 11 through 0
 *
 * Inverse mode:
 *     ascending unscaled DIT stages 0 through 11
 *
 * The engine issues one eight-coefficient group per clock and drains the
 * pipeline before advancing to the next stage.
 *
 * External memories must provide synchronous one-clock reads.
 *
 * Transform timing:
 *
 *     12 stages * 523 clocks/stage = 6276 clocks
 *
 * Initiation interval:
 *
 *     one four-butterfly group per clock
 */
module ntt4096_four_butterfly_pipeline_engine_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        start,
    input  logic        inverse_mode,

    input  logic [31:0] modulus,
    input  logic [30:0] modulus_mu,

    output logic             coefficient_read_valid,
    output logic [7:0][11:0] coefficient_read_address,
    input  logic             coefficient_read_data_valid,
    input  logic [7:0][31:0] coefficient_read_data,

    output logic             twiddle_read_valid,
    output logic [3:0][11:0] twiddle_read_address,
    input  logic [3:0][31:0] twiddle_read_data,

    output logic             coefficient_write_valid,
    output logic [7:0][11:0] coefficient_write_address,
    output logic [7:0][31:0] coefficient_write_data,

    output logic        busy,
    output logic        done,
    output logic [31:0] cycles,
    output logic [14:0] butterfly_count
);

    localparam logic [8:0] LAST_GROUP =
        9'd511;

    localparam logic [9:0] GROUPS_PER_STAGE =
        10'd512;

    localparam logic [14:0] TOTAL_BUTTERFLIES =
        15'd24576;

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_ISSUE,
        STATE_DRAIN
    } state_t;

    state_t state;

    logic [31:0] modulus_register;
    logic [30:0] modulus_mu_register;
    logic        inverse_mode_register;

    logic [3:0] current_stage;
    logic [8:0] issue_group;
    logic [9:0] writes_in_stage;

    logic [7:0][11:0] schedule_address;

    ntt4096_four_butterfly_schedule_core schedule (
        .stage       (current_stage),
        .group_index (issue_group),
        .address     (schedule_address)
    );

    logic [12:0] stage_one;
    logic [11:0] twiddle_mask;
    logic [12:0] twiddle_stage_base;

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

    assign coefficient_read_valid =
        state == STATE_ISSUE;

    assign coefficient_read_address =
        schedule_address;

    assign twiddle_read_valid =
        state == STATE_ISSUE;

    /*
     * One cycle after an issue, the external coefficient and twiddle
     * memories present the requested data.
     */
    logic transform_read_data_valid;

    /*
     * The issued address enters its delay line on the same edge that
     * launches the external BRAM reads. Ten registers align it with the
     * registered butterfly output-valid cycle.
     */
    logic [7:0][11:0] issue_address_register;
    logic [9:0][7:0][11:0] write_address_pipeline;

    integer address_delay_index;

    logic [3:0]       butterfly_output_valid;
    logic [3:0][31:0] butterfly_out_a;
    logic [3:0][31:0] butterfly_out_b;

    generate
        genvar butterfly_index;

        for (
            butterfly_index = 0;
            butterfly_index < 4;
            butterfly_index = butterfly_index + 1
        )
        begin : butterflies
            ntt4096_dual_mode_butterfly_pipeline_core butterfly (
                .clk          (clk),
                .reset_n      (reset_n),

                .input_valid  (
                    transform_read_data_valid
                    && coefficient_read_data_valid
                ),

                .inverse_mode (inverse_mode_register),

                .a            (
                    coefficient_read_data[
                        2 * butterfly_index
                    ]
                ),

                .b            (
                    coefficient_read_data[
                        2 * butterfly_index + 1
                    ]
                ),

                .omega        (
                    twiddle_read_data[
                        butterfly_index
                    ]
                ),

                .q            (modulus_register),
                .mu           (modulus_mu_register),

                .output_valid (
                    butterfly_output_valid[
                        butterfly_index
                    ]
                ),

                .out_a        (
                    butterfly_out_a[
                        butterfly_index
                    ]
                ),

                .out_b        (
                    butterfly_out_b[
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

    wire all_butterfly_output_valid =
        &butterfly_output_valid;

    wire any_butterfly_output_valid =
        |butterfly_output_valid;

    assign coefficient_write_valid =
        all_butterfly_output_valid;

    assign coefficient_write_address =
        write_address_pipeline[9];

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            modulus_register <=
                32'd0;

            modulus_mu_register <=
                31'd0;

            inverse_mode_register <=
                1'b0;

            current_stage <=
                4'd0;

            issue_group <=
                9'd0;

            writes_in_stage <=
                10'd0;

            transform_read_data_valid <=
                1'b0;

            issue_address_register <=
                '0;

            write_address_pipeline <=
                '0;

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

            transform_read_data_valid <=
                state == STATE_ISSUE;

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            write_address_pipeline[0] <=
                issue_address_register;

            for (
                address_delay_index = 1;
                address_delay_index < 10;
                address_delay_index = address_delay_index + 1
            )
            begin
                write_address_pipeline[address_delay_index] <=
                    write_address_pipeline[
                        address_delay_index - 1
                    ];
            end

            if (state == STATE_ISSUE)
            begin
                issue_address_register <=
                    schedule_address;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start)
                    begin
                        modulus_register <=
                            modulus;

                        modulus_mu_register <=
                            modulus_mu;

                        inverse_mode_register <=
                            inverse_mode;

                        current_stage <=
                            inverse_mode
                                ? 4'd0
                                : 4'd11;

                        issue_group <=
                            9'd0;

                        writes_in_stage <=
                            10'd0;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        butterfly_count <=
                            15'd0;

                        state <=
                            STATE_ISSUE;
                    end
                end

                STATE_ISSUE:
                begin
                    if (issue_group == LAST_GROUP)
                    begin
                        issue_group <=
                            9'd0;

                        state <=
                            STATE_DRAIN;
                    end
                    else
                    begin
                        issue_group <=
                            issue_group + 1'b1;
                    end
                end

                STATE_DRAIN:
                begin
                    /*
                     * Stage and transform completion are driven by
                     * coefficient_write_valid below.
                     */
                end

                default:
                begin
                    state <=
                        STATE_IDLE;

                    busy <=
                        1'b0;
                end
            endcase

            if (coefficient_write_valid)
            begin
                butterfly_count <=
                    butterfly_count + 3'd4;

                if (
                    writes_in_stage
                    == GROUPS_PER_STAGE - 1'b1
                )
                begin
                    writes_in_stage <=
                        10'd0;

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
                    else
                    begin
                        current_stage <=
                            inverse_mode_register
                                ? current_stage + 1'b1
                                : current_stage - 1'b1;

                        issue_group <=
                            9'd0;

                        state <=
                            STATE_ISSUE;
                    end
                end
                else
                begin
                    writes_in_stage <=
                        writes_in_stage + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            any_butterfly_output_valid
            && !all_butterfly_output_valid
        )
        begin
            $display(
                "ERROR: external-memory butterfly lane valid mismatch: %b",
                butterfly_output_valid
            );

            $fatal(1);
        end

        if (
            transform_read_data_valid
            && !coefficient_read_data_valid
        )
        begin
            $display(
                "ERROR: external coefficient memory missed a scheduled read"
            );

            $fatal(1);
        end
    end

`endif

endmodule
