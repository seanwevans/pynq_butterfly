`timescale 1ns/1ps

/*
 * N=256 radix-2 DIT butterfly schedule generator.
 *
 * The current operation remains stable until advance is asserted.
 * This lets a controller hold the addresses while waiting for BRAM
 * reads and the modular multiplier.
 *
 * For stage s:
 *
 *     half       = 2^s
 *     block_size = 2^(s+1)
 *
 * For butterfly index k within the stage:
 *
 *     block       = floor(k / half)
 *     local_index = k mod half
 *
 *     address_a = block * block_size + local_index
 *     address_b = address_a + half
 *
 * Compact twiddle ROM layout:
 *
 *     stage_base     = 2^s - 1
 *     twiddle_address = stage_base + local_index
 *
 * Each stage contains exactly N/2 = 128 butterflies.
 * Eight stages therefore produce 1024 butterflies.
 */
module ntt256_schedule_core (
    input  logic       clk,
    input  logic       reset_n,

    input  logic       start,
    input  logic       advance,

    output logic       busy,
    output logic       valid,
    output logic       done,

    output logic [9:0] operation_index,
    output logic [2:0] stage,
    output logic [6:0] butterfly_index,

    output logic [7:0] address_a,
    output logic [7:0] address_b,
    output logic [7:0] twiddle_address
);

    import ntt256_profile_pkg::*;

    logic [2:0] stage_reg;
    logic [6:0] butterfly_reg;

    integer half_value;
    integer block_value;
    integer local_value;
    integer address_value;
    integer twiddle_value;

    assign valid = busy;

    always @*
    begin
        stage            = stage_reg;
        butterfly_index  = butterfly_reg;

        operation_index =
            (stage_reg * 10'd128)
            + butterfly_reg;

        half_value =
            1 << stage_reg;

        block_value =
            butterfly_reg >> stage_reg;

        local_value =
            butterfly_reg & (half_value - 1);

        address_value =
            (
                block_value
                << (stage_reg + 1)
            )
            + local_value;

        twiddle_value =
            (
                1 << stage_reg
            )
            - 1
            + local_value;

        address_a =
            address_value[7:0];

        address_b =
            (
                address_value
                + half_value
            );

        twiddle_address =
            twiddle_value[7:0];
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            stage_reg     <= 3'd0;
            butterfly_reg <= 7'd0;

            busy <= 1'b0;
            done <= 1'b0;
        end
        else
        begin
            done <= 1'b0;

            if (!busy)
            begin
                if (start)
                begin
                    stage_reg     <= 3'd0;
                    butterfly_reg <= 7'd0;

                    busy <= 1'b1;
                end
            end
            else if (advance)
            begin
                if (
                    (stage_reg == 3'd7) &&
                    (butterfly_reg == 7'd127)
                )
                begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
                else if (butterfly_reg == 7'd127)
                begin
                    stage_reg <=
                        stage_reg + 1'b1;

                    butterfly_reg <= 7'd0;
                end
                else
                begin
                    butterfly_reg <=
                        butterfly_reg + 1'b1;
                end
            end
        end
    end

endmodule
