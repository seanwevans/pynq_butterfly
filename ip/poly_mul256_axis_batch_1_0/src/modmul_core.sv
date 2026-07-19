`timescale 1ns/1ps

/*
 * Two-bit-per-cycle modular multiplier with flattened reduction.
 *
 * Preconditions during ordinary operation:
 *
 *     q != 0
 *     a < q
 *     b < q
 *
 * Each iteration consumes two bits of b:
 *
 *     acc' = acc + digit*x mod q
 *     x'   = 4*x mod q
 *
 * where digit is in {0,1,2,3}.
 *
 * Values before reduction are strictly less than 4q, so reduction
 * selects among value, value-q, value-2q, and value-3q.
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

    logic [31:0] acc;
    logic [31:0] x;
    logic [31:0] y;
    logic [31:0] modulus;

    logic [3:0] iteration;

    /*
     * Thirty-four bits hold values below 4q for every 32-bit q.
     */
    logic [33:0] q1;
    logic [33:0] q2;
    logic [33:0] q3;

    logic [33:0] x1_raw;
    logic [33:0] x2_raw;
    logic [33:0] x3_raw;
    logic [33:0] x4_raw;

    logic [33:0] selected_raw;
    logic [33:0] acc_sum_raw;

    /*
     * One extra bit distinguishes a nonnegative subtraction result
     * from unsigned underflow.
     */
    logic [34:0] acc_minus_q1;
    logic [34:0] acc_minus_q2;
    logic [34:0] acc_minus_q3;

    logic [34:0] x4_minus_q1;
    logic [34:0] x4_minus_q2;
    logic [34:0] x4_minus_q3;

    logic [33:0] reduced_acc_raw;
    logic [33:0] reduced_x4_raw;

    logic [31:0] next_acc;
    logic [31:0] next_x;

    assign q1 =
        {2'b00, modulus};

    assign q2 =
        q1 << 1;

    assign q3 =
        q1 + q2;

    assign x1_raw =
        {2'b00, x};

    assign x2_raw =
        x1_raw << 1;

    assign x3_raw =
        x1_raw + x2_raw;

    assign x4_raw =
        x1_raw << 2;

    assign selected_raw =
        (y[1:0] == 2'b00)
            ? 34'd0
        : (y[1:0] == 2'b01)
            ? x1_raw
        : (y[1:0] == 2'b10)
            ? x2_raw
            : x3_raw;

    assign acc_sum_raw =
        {2'b00, acc}
        + selected_raw;

    /*
     * These subtraction paths are independent and may be implemented
     * in parallel. Bit 34 is one after unsigned underflow and zero
     * when the subtraction is nonnegative.
     */
    assign acc_minus_q1 =
        {1'b0, acc_sum_raw}
        - {1'b0, q1};

    assign acc_minus_q2 =
        {1'b0, acc_sum_raw}
        - {1'b0, q2};

    assign acc_minus_q3 =
        {1'b0, acc_sum_raw}
        - {1'b0, q3};

    assign x4_minus_q1 =
        {1'b0, x4_raw}
        - {1'b0, q1};

    assign x4_minus_q2 =
        {1'b0, x4_raw}
        - {1'b0, q2};

    assign x4_minus_q3 =
        {1'b0, x4_raw}
        - {1'b0, q3};

    assign reduced_acc_raw =
        !acc_minus_q3[34]
            ? acc_minus_q3[33:0]
        : !acc_minus_q2[34]
            ? acc_minus_q2[33:0]
        : !acc_minus_q1[34]
            ? acc_minus_q1[33:0]
            : acc_sum_raw;

    assign reduced_x4_raw =
        !x4_minus_q3[34]
            ? x4_minus_q3[33:0]
        : !x4_minus_q2[34]
            ? x4_minus_q2[33:0]
        : !x4_minus_q1[34]
            ? x4_minus_q1[33:0]
            : x4_raw;

    assign next_acc =
        reduced_acc_raw[31:0];

    assign next_x =
        reduced_x4_raw[31:0];

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
                        next_x;

                    y <=
                        y >> 2;

                    iteration <=
                        iteration + 1'b1;
                end
            end
        end
    end

endmodule
