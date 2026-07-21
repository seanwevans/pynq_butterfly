`timescale 1ns/1ps

/*
 * Fully pipelined runtime-modulus radix-2 NTT butterfly.
 *
 * Forward DIF:
 *
 *     out_a = a + b mod q
 *     out_b = (a - b) * omega mod q
 *
 * Inverse DIT:
 *
 *     p     = b * omega mod q
 *     out_a = a + p mod q
 *     out_b = a - p mod q
 *
 * The embedded Barrett multiplier has latency 7 and II=1. This wrapper
 * adds an input isolation register and a registered output stage.
 *
 * Input-to-output latency: 9 clocks
 * Initiation interval:     1 clock
 */
module ntt4096_dual_mode_butterfly_pipeline_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        input_valid,
    input  logic        inverse_mode,

    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] omega,
    input  logic [31:0] q,
    input  logic [30:0] mu,

    output logic        output_valid,
    output logic [31:0] out_a,
    output logic [31:0] out_b
);

    logic        input_valid_register;
    logic        inverse_mode_register;
    logic [31:0] a_register;
    logic [31:0] b_register;
    logic [31:0] omega_register;
    logic [31:0] q_register;
    logic [30:0] mu_register;

    logic [32:0] input_sum_extended;
    logic [31:0] input_sum_reduced;
    logic [31:0] input_difference_reduced;
    logic [31:0] multiplier_a;

    assign input_sum_extended =
        {1'b0, a_register}
        + {1'b0, b_register};

    assign input_sum_reduced =
        input_sum_extended >= {1'b0, q_register}
            ? input_sum_extended[31:0] - q_register
            : input_sum_extended[31:0];

    assign input_difference_reduced =
        a_register >= b_register
            ? a_register - b_register
            : a_register + q_register - b_register;

    assign multiplier_a =
        inverse_mode_register
            ? b_register
            : input_difference_reduced;

    logic        multiplier_output_valid;
    logic [31:0] multiplier_result;

    modmul_barrett60_pipeline_split_core multiplier (
        .clk          (clk),
        .reset_n      (reset_n),

        .input_valid  (input_valid_register),
        .a            (multiplier_a),
        .b            (omega_register),
        .q            (q_register),
        .mu           (mu_register),

        .output_valid (multiplier_output_valid),
        .result       (multiplier_result)
    );

    /*
     * The metadata enters this delay line on the same edge that the
     * multiplier accepts its operands. Eight registers align it with
     * the multiplier result as sampled by this wrapper's output stage.
     */
    logic [7:0]       inverse_mode_delay;
    logic [7:0][31:0] a_delay;
    logic [7:0][31:0] sum_delay;
    logic [7:0][31:0] q_delay;

    logic [32:0] output_sum_extended;
    logic [31:0] output_sum_reduced;
    logic [31:0] output_difference_reduced;

    assign output_sum_extended =
        {1'b0, a_delay[7]}
        + {1'b0, multiplier_result};

    assign output_sum_reduced =
        output_sum_extended >= {1'b0, q_delay[7]}
            ? output_sum_extended[31:0] - q_delay[7]
            : output_sum_extended[31:0];

    assign output_difference_reduced =
        a_delay[7] >= multiplier_result
            ? a_delay[7] - multiplier_result
            : a_delay[7] + q_delay[7] - multiplier_result;

    integer delay_index;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            input_valid_register <=
                1'b0;

            inverse_mode_register <=
                1'b0;

            a_register <=
                32'd0;

            b_register <=
                32'd0;

            omega_register <=
                32'd0;

            q_register <=
                32'd0;

            mu_register <=
                31'd0;

            inverse_mode_delay <=
                8'd0;

            a_delay <=
                '0;

            sum_delay <=
                '0;

            q_delay <=
                '0;

            output_valid <=
                1'b0;

            out_a <=
                32'd0;

            out_b <=
                32'd0;
        end
        else
        begin
            input_valid_register <=
                input_valid;

            if (input_valid)
            begin
                inverse_mode_register <=
                    inverse_mode;

                a_register <=
                    a;

                b_register <=
                    b;

                omega_register <=
                    omega;

                q_register <=
                    q;

                mu_register <=
                    mu;
            end

            inverse_mode_delay[0] <=
                inverse_mode_register;

            a_delay[0] <=
                a_register;

            sum_delay[0] <=
                input_sum_reduced;

            q_delay[0] <=
                q_register;

            for (
                delay_index = 1;
                delay_index < 8;
                delay_index = delay_index + 1
            )
            begin
                inverse_mode_delay[delay_index] <=
                    inverse_mode_delay[delay_index - 1];

                a_delay[delay_index] <=
                    a_delay[delay_index - 1];

                sum_delay[delay_index] <=
                    sum_delay[delay_index - 1];

                q_delay[delay_index] <=
                    q_delay[delay_index - 1];
            end

            output_valid <=
                multiplier_output_valid;

            if (multiplier_output_valid)
            begin
                if (inverse_mode_delay[7])
                begin
                    out_a <=
                        output_sum_reduced;

                    out_b <=
                        output_difference_reduced;
                end
                else
                begin
                    out_a <=
                        sum_delay[7];

                    out_b <=
                        multiplier_result;
                end
            end
        end
    end

endmodule
