`timescale 1ns/1ps

/*
 * Stallable conflict-free two-butterfly schedule for N=4096.
 *
 * Each stage contains 2048 radix-2 butterflies. This scheduler emits
 * two disjoint butterflies per entry, reducing the stage to 1024
 * paired entries. The current entry remains stable until advance is
 * asserted by the arithmetic controller.
 *
 * descending=1 visits stage bits 11..0 for forward DIF.
 * descending=0 visits stage bits 0..11 for inverse DIT.
 */
module ntt4096_paired_schedule_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        start,
    input  logic        descending,
    input  logic        advance,

    output logic        busy,
    output logic        valid,
    output logic        done,

    output logic [3:0]  stage_bit,
    output logic [9:0]  pair_index,

    output logic [11:0] address0_a,
    output logic [11:0] address0_b,
    output logic [11:0] address1_a,
    output logic [11:0] address1_b,

    output logic [11:0] twiddle_address0,
    output logic [11:0] twiddle_address1
);

    logic [3:0] current_stage;
    logic [9:0] current_pair;
    logic       current_descending;

    logic [3:0] companion_bit;

    logic [11:0] base_address;
    logic [11:0] second_base_address;

    logic [12:0] stage_one;
    logic [11:0] twiddle_mask;
    logic [12:0] twiddle_stage_base;

    logic [11:0] j0;
    logic [11:0] j1;

    function automatic [11:0] deposit_pair_index;
        input [9:0] packed_index;
        input [3:0] skip_bit0;
        input [3:0] skip_bit1;

        integer destination_bit;
        integer source_bit;

        begin
            deposit_pair_index =
                12'd0;

            source_bit =
                0;

            for (
                destination_bit = 0;
                destination_bit < 12;
                destination_bit = destination_bit + 1
            )
            begin
                if (
                    destination_bit != skip_bit0
                    && destination_bit != skip_bit1
                )
                begin
                    deposit_pair_index[destination_bit] =
                        packed_index[source_bit];

                    source_bit =
                        source_bit + 1;
                end
            end
        end
    endfunction

    assign valid =
        busy;

    assign stage_bit =
        current_stage;

    assign pair_index =
        current_pair;

    assign companion_bit =
        current_stage < 4'd11
            ? current_stage + 1'b1
            : 4'd10;

    assign base_address =
        deposit_pair_index(
            current_pair,
            current_stage,
            companion_bit
        );

    assign second_base_address =
        base_address
        | (12'd1 << companion_bit);

    assign address0_a =
        base_address;

    assign address0_b =
        base_address
        | (12'd1 << current_stage);

    assign address1_a =
        second_base_address;

    assign address1_b =
        second_base_address
        | (12'd1 << current_stage);

    assign stage_one =
        13'd1 << current_stage;

    assign twiddle_mask =
        stage_one[11:0] - 1'b1;

    assign twiddle_stage_base =
        stage_one - 1'b1;

    assign j0 =
        address0_a
        & twiddle_mask;

    assign j1 =
        address1_a
        & twiddle_mask;

    assign twiddle_address0 =
        twiddle_stage_base[11:0]
        + j0;

    assign twiddle_address1 =
        twiddle_stage_base[11:0]
        + j1;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            busy <=
                1'b0;

            done <=
                1'b0;

            current_stage <=
                4'd0;

            current_pair <=
                10'd0;

            current_descending <=
                1'b0;
        end
        else
        begin
            done <=
                1'b0;

            if (start && !busy)
            begin
                busy <=
                    1'b1;

                current_descending <=
                    descending;

                current_stage <=
                    descending
                        ? 4'd11
                        : 4'd0;

                current_pair <=
                    10'd0;
            end
            else if (busy && advance)
            begin
                if (current_pair == 10'd1023)
                begin
                    current_pair <=
                        10'd0;

                    if (
                        (
                            current_descending
                            && current_stage == 4'd0
                        )
                        || (
                            !current_descending
                            && current_stage == 4'd11
                        )
                    )
                    begin
                        busy <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                    else if (current_descending)
                    begin
                        current_stage <=
                            current_stage - 1'b1;
                    end
                    else
                    begin
                        current_stage <=
                            current_stage + 1'b1;
                    end
                end
                else
                begin
                    current_pair <=
                        current_pair + 1'b1;
                end
            end
        end
    end

endmodule
