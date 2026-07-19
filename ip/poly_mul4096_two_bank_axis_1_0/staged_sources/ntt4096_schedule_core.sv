`timescale 1ns/1ps

/*
 * N=4096 radix-2 DIT butterfly scheduler.
 *
 * Operation order matches:
 *
 *     model/golden_n4096/butterfly_schedule.csv
 *
 * For stage s:
 *
 *     half_size          = 2^s
 *     span_size          = 2^(s+1)
 *     groups_per_stage   = 4096 / span_size
 *     twiddle_stage_base = 2^s - 1
 *
 * The current schedule entry remains unchanged until advance is
 * asserted. This allows the arithmetic datapath to stall the scheduler
 * for any number of clocks.
 */
module ntt4096_schedule_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,
    input  logic        advance,

    output logic        busy,
    output logic        valid,
    output logic        done,

    output logic [14:0] operation,
    output logic [3:0]  stage,
    output logic [11:0] group,
    output logic [11:0] j,

    output logic [11:0] left_addr,
    output logic [11:0] right_addr,
    output logic [11:0] twiddle_addr
);

    import ntt4096_profile_pkg::*;

    logic [12:0] half_size;
    logic [12:0] span_size;
    logic [12:0] groups_per_stage;
    logic [12:0] group_base;
    logic [12:0] twiddle_stage_base;

    logic [12:0] left_addr_ext;
    logic [12:0] right_addr_ext;
    logic [12:0] twiddle_addr_ext;

    assign left_addr_ext =
        group_base
        + {1'b0, j};

    assign right_addr_ext =
        left_addr_ext
        + half_size;

    assign twiddle_addr_ext =
        twiddle_stage_base
        + {1'b0, j};

    assign left_addr =
        left_addr_ext[11:0];

    assign right_addr =
        right_addr_ext[11:0];

    assign twiddle_addr =
        twiddle_addr_ext[11:0];

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            busy <=
                1'b0;

            valid <=
                1'b0;

            done <=
                1'b0;

            operation <=
                15'd0;

            stage <=
                4'd0;

            group <=
                12'd0;

            j <=
                12'd0;

            half_size <=
                13'd1;

            span_size <=
                13'd2;

            groups_per_stage <=
                13'd2048;

            group_base <=
                13'd0;

            twiddle_stage_base <=
                13'd0;
        end
        else
        begin
            done <=
                1'b0;

            if (start && !busy)
            begin
                busy <=
                    1'b1;

                valid <=
                    1'b1;

                operation <=
                    15'd0;

                stage <=
                    4'd0;

                group <=
                    12'd0;

                j <=
                    12'd0;

                half_size <=
                    13'd1;

                span_size <=
                    13'd2;

                groups_per_stage <=
                    13'd2048;

                group_base <=
                    13'd0;

                twiddle_stage_base <=
                    13'd0;
            end
            else if (busy && valid && advance)
            begin
                if (
                    operation
                    == NTT_BUTTERFLIES_PER_TRANSFORM - 1
                )
                begin
                    busy <=
                        1'b0;

                    valid <=
                        1'b0;

                    done <=
                        1'b1;
                end
                else
                begin
                    operation <=
                        operation + 1'b1;

                    if (
                        {1'b0, j}
                        == half_size - 1'b1
                    )
                    begin
                        j <=
                            12'd0;

                        if (
                            {1'b0, group}
                            == groups_per_stage - 1'b1
                        )
                        begin
                            stage <=
                                stage + 1'b1;

                            group <=
                                12'd0;

                            group_base <=
                                13'd0;

                            half_size <=
                                half_size << 1;

                            span_size <=
                                span_size << 1;

                            groups_per_stage <=
                                groups_per_stage >> 1;

                            twiddle_stage_base <=
                                (twiddle_stage_base << 1)
                                + 1'b1;
                        end
                        else
                        begin
                            group <=
                                group + 1'b1;

                            group_base <=
                                group_base
                                + span_size;
                        end
                    end
                    else
                    begin
                        j <=
                            j + 1'b1;
                    end
                end
            end
        end
    end

endmodule
