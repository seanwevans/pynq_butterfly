`timescale 1ns/1ps

module modmul_core_radix2 (
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

    logic [31:0] acc;
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] modulus;
    logic [5:0]  iteration;

    logic [32:0] acc_plus_x;
    logic [32:0] doubled_x;
    logic [32:0] modulus_ext;

    logic [32:0] reduced_acc_ext;
    logic [32:0] reduced_double_ext;

    logic [31:0] reduced_acc;
    logic [31:0] reduced_double;
    logic [31:0] next_acc;

    assign acc_plus_x = {1'b0, acc} + {1'b0, x};
    assign doubled_x  = {1'b0, x} << 1;
    assign modulus_ext = {1'b0, modulus};

    assign reduced_acc_ext =
        (acc_plus_x >= modulus_ext)
            ? acc_plus_x - modulus_ext
            : acc_plus_x;

    assign reduced_double_ext =
        (doubled_x >= modulus_ext)
            ? doubled_x - modulus_ext
            : doubled_x;

    assign reduced_acc =
        reduced_acc_ext[31:0];

    assign reduced_double =
        reduced_double_ext[31:0];

    assign next_acc =
        y[0] ? reduced_acc : acc;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            acc       <= 32'd0;
            x         <= 32'd0;
            y         <= 32'd0;
            modulus   <= 32'd0;
            iteration <= 6'd0;

            result <= 32'd0;
            busy   <= 1'b0;
            done   <= 1'b0;
        end
        else
        begin
            // Completion is a one-clock pulse.
            done <= 1'b0;

            if (start && !busy)
            begin
                acc       <= 32'd0;
                x         <= a;
                y         <= b;
                modulus   <= q;
                iteration <= 6'd0;
                result    <= 32'd0;

                if (q == 32'd0)
                begin
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    result <= 32'd0;
                end
                else
                begin
                    busy <= 1'b1;
                end
            end
            else if (busy)
            begin
                if (iteration == 6'd31)
                begin
                    // Include the final multiplier bit.
                    result <= next_acc;
                    acc    <= next_acc;

                    busy <= 1'b0;
                    done <= 1'b1;
                end
                else
                begin
                    acc <= next_acc;
                    x   <= reduced_double;
                    y   <= y >> 1;

                    iteration <= iteration + 1'b1;
                end
            end
        end
    end

endmodule
