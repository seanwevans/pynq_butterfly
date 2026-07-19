`timescale 1ns/1ps

/*
 * Radix-2 decimation-in-frequency butterfly.
 *
 *     sum        = a + b mod q
 *     difference = a - b mod q
 *
 *     out_a = sum
 *     out_b = difference * omega mod q
 *
 * Its handshake latency matches butterfly_core.
 */
module butterfly_dif_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] omega,
    input  logic [31:0] q,

    output logic [31:0] out_a,
    output logic [31:0] out_b,
    output logic        busy,
    output logic        done
);

    logic [32:0] sum_extended;

    logic [31:0] reduced_sum;
    logic [31:0] reduced_difference;

    logic multiplier_start;
    logic multiplier_busy;
    logic multiplier_done;

    logic [31:0] multiplier_result;

    logic [31:0] sum_register;

    assign sum_extended =
        {1'b0, a}
        + {1'b0, b};

    assign reduced_sum =
        sum_extended >= {1'b0, q}
            ? sum_extended - {1'b0, q}
            : sum_extended[31:0];

    assign reduced_difference =
        a >= b
            ? a - b
            : a + q - b;

    assign multiplier_start =
        start
        && !busy;

    modmul_core multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (multiplier_start),

        .a       (reduced_difference),
        .b       (omega),
        .q       (q),

        .result  (multiplier_result),
        .busy    (multiplier_busy),
        .done    (multiplier_done)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            out_a <=
                32'd0;

            out_b <=
                32'd0;

            busy <=
                1'b0;

            done <=
                1'b0;

            sum_register <=
                32'd0;
        end
        else
        begin
            done <=
                1'b0;

            if (
                start
                && !busy
            )
            begin
                busy <=
                    1'b1;

                sum_register <=
                    reduced_sum;
            end

            if (multiplier_done)
            begin
                out_a <=
                    sum_register;

                out_b <=
                    multiplier_result;

                busy <=
                    1'b0;

                done <=
                    1'b1;
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            start
            && busy
        )
        begin
            $display(
                "ERROR: DIF butterfly start attempted while busy"
            );

            $fatal(1);
        end

        if (
            multiplier_done
            && !busy
        )
        begin
            $display(
                "ERROR: DIF multiplier completed while butterfly was idle"
            );

            $fatal(1);
        end
    end

`endif

endmodule
