`timescale 1ns/1ps

/*
 * Simulation-only exact behavioral replacement for the seven-cycle
 * modmul_barrett60_pipeline_split_core.
 *
 * This isolates the EVPT/EV12 sequencer and legacy-core framing test from
 * multiplier implementation details. The production Vivado build does not
 * compile this file.
 */
module modmul_barrett60_pipeline_split_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        input_valid,
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] q,
    input  logic [30:0] mu,

    output logic        output_valid,
    output logic [31:0] result
);

    logic [6:0] valid_pipeline;
    logic [31:0] result_pipeline [0:6];

    longint unsigned product_value;
    integer stage_index;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            valid_pipeline <=
                7'd0;

            output_valid <=
                1'b0;

            result <=
                32'd0;

            for (
                stage_index = 0;
                stage_index < 7;
                stage_index = stage_index + 1
            )
            begin
                result_pipeline[stage_index] <=
                    32'd0;
            end
        end
        else
        begin
            valid_pipeline[0] <=
                input_valid;

            for (
                stage_index = 1;
                stage_index < 7;
                stage_index = stage_index + 1
            )
            begin
                valid_pipeline[stage_index] <=
                    valid_pipeline[stage_index - 1];

                result_pipeline[stage_index] <=
                    result_pipeline[stage_index - 1];
            end

            if (input_valid)
            begin
                product_value =
                    a;

                product_value =
                    product_value * b;

                result_pipeline[0] <=
                    product_value % q;
            end

            output_valid <=
                valid_pipeline[6];

            if (valid_pipeline[6])
            begin
                result <=
                    result_pipeline[6];
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (reset_n && input_valid)
        begin
            if (q == 0 || a >= q || b >= q)
            begin
                $display(
                    "ERROR: invalid behavioral modmul input a=%0d b=%0d q=%0d",
                    a,
                    b,
                    q
                );

                $fatal(1);
            end

            if (mu != 64'h1000000000000000 / q)
            begin
                $display(
                    "ERROR: invalid behavioral modmul reciprocal"
                );

                $fatal(1);
            end
        end
    end

`endif

endmodule
