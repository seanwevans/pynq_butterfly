`timescale 1ns/1ps

/*
 * Two-bit-per-cycle modular multiplier.
 *
 * Preconditions for normal arithmetic:
 *
 *     q != 0
 *     0 <= a < q
 *     0 <= b < q
 *
 * Computes:
 *
 *     result = a * b mod q
 *
 * The interface matches modmul_core, but the arithmetic loop requires
 * 16 iterations instead of 32.
 */
module modmul_core_radix4 (
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

    logic [3:0] iteration;

    logic [32:0] modulus_ext;

    /*
     * x2 = 2x mod q
     */
    logic [32:0] twice_x_ext;
    logic [32:0] reduced_x2_ext;
    logic [31:0] x2;

    /*
     * x3 = 3x mod q
     *
     * Because x and x2 are each less than q, their sum is less than
     * 2q and requires at most one subtraction.
     */
    logic [32:0] x2_plus_x_ext;
    logic [32:0] reduced_x3_ext;
    logic [31:0] x3;

    /*
     * x4 = 4x mod q = 2(x2) mod q
     */
    logic [32:0] twice_x2_ext;
    logic [32:0] reduced_x4_ext;
    logic [31:0] x4;

    /*
     * Select 0x, 1x, 2x, or 3x from the next two multiplier bits.
     */
    logic [31:0] selected_addend;

    logic [32:0] acc_plus_addend_ext;
    logic [32:0] reduced_acc_ext;
    logic [31:0] next_acc;

    assign modulus_ext =
        {1'b0, modulus};

    assign twice_x_ext =
        {1'b0, x} << 1;

    assign reduced_x2_ext =
        (twice_x_ext >= modulus_ext)
            ? twice_x_ext - modulus_ext
            : twice_x_ext;

    assign x2 =
        reduced_x2_ext[31:0];

    assign x2_plus_x_ext =
        {1'b0, x2} + {1'b0, x};

    assign reduced_x3_ext =
        (x2_plus_x_ext >= modulus_ext)
            ? x2_plus_x_ext - modulus_ext
            : x2_plus_x_ext;

    assign x3 =
        reduced_x3_ext[31:0];

    assign twice_x2_ext =
        {1'b0, x2} << 1;

    assign reduced_x4_ext =
        (twice_x2_ext >= modulus_ext)
            ? twice_x2_ext - modulus_ext
            : twice_x2_ext;

    assign x4 =
        reduced_x4_ext[31:0];

    always_comb
    begin
        case (y[1:0])
            2'b00:
            begin
                selected_addend =
                    32'd0;
            end

            2'b01:
            begin
                selected_addend =
                    x;
            end

            2'b10:
            begin
                selected_addend =
                    x2;
            end

            default:
            begin
                selected_addend =
                    x3;
            end
        endcase
    end

    /*
     * acc and selected_addend are both reduced residues. Their sum is
     * less than 2q and therefore requires at most one subtraction.
     */
    assign acc_plus_addend_ext =
        {1'b0, acc}
        + {1'b0, selected_addend};

    assign reduced_acc_ext =
        (acc_plus_addend_ext >= modulus_ext)
            ? acc_plus_addend_ext - modulus_ext
            : acc_plus_addend_ext;

    assign next_acc =
        reduced_acc_ext[31:0];

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            acc <=
                32'd0;

            x <=
                32'd0;

            y <=
                32'd0;

            modulus <=
                32'd0;

            iteration <=
                4'd0;

            result <=
                32'd0;

            busy <=
                1'b0;

            done <=
                1'b0;
        end
        else
        begin
            /*
             * Completion remains a one-clock pulse.
             */
            done <=
                1'b0;

            if (start && !busy)
            begin
                acc <=
                    32'd0;

                x <=
                    a;

                y <=
                    b;

                modulus <=
                    q;

                iteration <=
                    4'd0;

                result <=
                    32'd0;

                if (q == 32'd0)
                begin
                    busy <=
                        1'b0;

                    done <=
                        1'b1;

                    result <=
                        32'd0;
                end
                else
                begin
                    busy <=
                        1'b1;
                end
            end
            else if (busy)
            begin
                /*
                 * Sixteen iterations consume all 32 multiplier bits.
                 */
                if (iteration == 4'd15)
                begin
                    result <=
                        next_acc;

                    acc <=
                        next_acc;

                    busy <=
                        1'b0;

                    done <=
                        1'b1;
                end
                else
                begin
                    acc <=
                        next_acc;

                    x <=
                        x4;

                    y <=
                        y >> 2;

                    iteration <=
                        iteration + 1'b1;
                end
            end
        end
    end

endmodule
