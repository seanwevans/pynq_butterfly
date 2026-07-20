`timescale 1ns/1ps

/*
 * Fast integration-only model of modmul_core.
 *
 * Compile this file instead of the iterative hardware modmul_core.sv
 * when validating the complete polynomial controller in Icarus.
 *
 * It preserves the module interface and the start/busy/done handshake,
 * but computes the exact modular product behaviorally and returns it
 * on the following clock. It must never be used for synthesis.
 */
module modmul_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] q,

    output logic [31:0] result,
    output logic        busy,
    output logic        done
);

    logic [63:0] full_product;
    logic [31:0] pending_result;

    assign full_product =
        {32'd0, a}
        * {32'd0, b};

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            result <=
                32'd0;

            pending_result <=
                32'd0;

            busy <=
                1'b0;

            done <=
                1'b0;
        end
        else
        begin
            done <=
                1'b0;

            if (start && !busy)
            begin
                pending_result <=
                    q == 32'd0
                        ? 32'd0
                        : full_product % q;

                busy <=
                    1'b1;
            end
            else if (busy)
            begin
                result <=
                    pending_result;

                busy <=
                    1'b0;

                done <=
                    1'b1;
            end
        end
    end

    always @(posedge clk)
    begin
        if (start && busy)
        begin
            $display(
                "ERROR: fast simulation modmul started while busy"
            );

            $fatal(1);
        end
    end

endmodule
