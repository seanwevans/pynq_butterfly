`timescale 1ns/1ps

/*
 * Runtime-modulus radix-2 butterfly using one iterative modmul_core.
 *
 * inverse_mode=0: forward DIF
 *
 *     out_a = a + b mod q
 *     out_b = (a - b) * omega mod q
 *
 * inverse_mode=1: inverse DIT
 *
 *     p     = b * omega mod q
 *     out_a = a + p mod q
 *     out_b = a - p mod q
 */
module ntt4096_dual_mode_butterfly_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        inverse_mode,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] omega,
    input  logic [31:0] q,

    output logic [31:0] out_a,
    output logic [31:0] out_b,
    output logic        busy,
    output logic        done
);

    logic [32:0] input_sum_extended;
    logic [31:0] input_sum_reduced;
    logic [31:0] input_difference_reduced;

    logic [32:0] output_sum_extended;
    logic [31:0] output_sum_reduced;
    logic [31:0] output_difference_reduced;

    logic [31:0] multiplier_a;
    logic [31:0] multiplier_result;
    logic        multiplier_start;
    logic        multiplier_busy;
    logic        multiplier_done;

    logic        inverse_mode_register;
    logic [31:0] a_register;
    logic [31:0] sum_register;
    logic [31:0] product_register;
    logic        finish_pending;

    assign input_sum_extended =
        {1'b0, a}
        + {1'b0, b};

    assign input_sum_reduced =
        input_sum_extended >= {1'b0, q}
            ? input_sum_extended[31:0] - q
            : input_sum_extended[31:0];

    assign input_difference_reduced =
        a >= b
            ? a - b
            : a + q - b;

    assign multiplier_a =
        inverse_mode
            ? b
            : input_difference_reduced;

    assign multiplier_start =
        start
        && !busy;

    assign output_sum_extended =
        {1'b0, a_register}
        + {1'b0, product_register};

    assign output_sum_reduced =
        output_sum_extended >= {1'b0, q}
            ? output_sum_extended[31:0] - q
            : output_sum_extended[31:0];

    assign output_difference_reduced =
        a_register >= product_register
            ? a_register - product_register
            : a_register + q - product_register;

    modmul_core multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (multiplier_start),

        .a       (multiplier_a),
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

            inverse_mode_register <=
                1'b0;

            a_register <=
                32'd0;

            sum_register <=
                32'd0;

            product_register <=
                32'd0;

            finish_pending <=
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

                inverse_mode_register <=
                    inverse_mode;

                a_register <=
                    a;

                sum_register <=
                    input_sum_reduced;
            end

            if (multiplier_done)
            begin
                product_register <=
                    multiplier_result;

                finish_pending <=
                    1'b1;
            end

            if (finish_pending)
            begin
                if (inverse_mode_register)
                begin
                    out_a <=
                        output_sum_reduced;

                    out_b <=
                        output_difference_reduced;
                end
                else
                begin
                    out_a <=
                        sum_register;

                    out_b <=
                        product_register;
                end

                busy <=
                    1'b0;

                done <=
                    1'b1;

                finish_pending <=
                    1'b0;
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (start && busy)
        begin
            $display(
                "ERROR: paired butterfly start attempted while busy"
            );

            $fatal(1);
        end

        if (multiplier_done && !busy)
        begin
            $display(
                "ERROR: paired butterfly multiplier completed while idle"
            );

            $fatal(1);
        end
    end

`endif

endmodule
