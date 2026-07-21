`timescale 1ns/1ps

/*
 * Four shared modular-arithmetic lanes.
 *
 * MODE_SCALAR:
 *
 *     The inverse butterfly identity
 *
 *         a = 0
 *         b = x
 *         omega = y
 *
 *     gives:
 *
 *         out_a = x * y mod q
 *
 *     so scalar phases reuse the same four Barrett multipliers as the
 *     forward and inverse NTT phases.
 *
 * MODE_FORWARD:
 *
 *     ordinary forward DIF butterfly
 *
 * MODE_INVERSE:
 *
 *     ordinary inverse DIT butterfly
 *
 * Latency: 9 clocks
 * II:      1 vector per clock
 */
module poly_mul4096_four_lane_arithmetic_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        input_valid,
    input  logic [1:0]  mode,

    input  logic [3:0][31:0] input_a,
    input  logic [3:0][31:0] input_b,
    input  logic [3:0][31:0] input_omega,

    input  logic [31:0] q,
    input  logic [30:0] mu,

    output logic             output_valid,
    output logic [3:0][31:0] output_a,
    output logic [3:0][31:0] output_b
);

    localparam logic [1:0] MODE_SCALAR =
        2'd0;

    localparam logic [1:0] MODE_FORWARD =
        2'd1;

    localparam logic [1:0] MODE_INVERSE =
        2'd2;

    logic [3:0] lane_output_valid;

    generate
        genvar lane_index;

        for (
            lane_index = 0;
            lane_index < 4;
            lane_index = lane_index + 1
        )
        begin : lanes
            logic lane_inverse_mode;
            logic [31:0] lane_a;
            logic [31:0] lane_b;
            logic [31:0] lane_omega;

            assign lane_inverse_mode =
                mode != MODE_FORWARD;

            assign lane_a =
                mode == MODE_SCALAR
                    ? 32'd0
                    : input_a[lane_index];

            assign lane_b =
                input_b[lane_index];

            assign lane_omega =
                mode == MODE_SCALAR
                    ? input_a[lane_index]
                    : input_omega[lane_index];

            /*
             * Scalar mode maps:
             *
             *     input_a = multiplier y
             *     input_b = multiplicand x
             */
            ntt4096_dual_mode_butterfly_pipeline_core lane (
                .clk          (clk),
                .reset_n      (reset_n),

                .input_valid  (input_valid),
                .inverse_mode (lane_inverse_mode),

                .a            (lane_a),
                .b            (lane_b),
                .omega        (lane_omega),

                .q            (q),
                .mu           (mu),

                .output_valid (lane_output_valid[lane_index]),
                .out_a        (output_a[lane_index]),
                .out_b        (output_b[lane_index])
            );
        end
    endgenerate

    assign output_valid =
        &lane_output_valid;

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            (|lane_output_valid)
            && !(&lane_output_valid)
        )
        begin
            $display(
                "ERROR: shared arithmetic lane valid mismatch: %b",
                lane_output_valid
            );

            $fatal(1);
        end

        if (
            reset_n
            && input_valid
            && mode == 2'd3
        )
        begin
            $display(
                "ERROR: invalid shared arithmetic mode"
            );

            $fatal(1);
        end
    end

`endif

endmodule
