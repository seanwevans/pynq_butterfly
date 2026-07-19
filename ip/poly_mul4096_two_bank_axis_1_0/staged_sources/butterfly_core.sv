`timescale 1ns/1ps

module butterfly_core (
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

    // Inputs required after the modular multiplication completes.
    logic [31:0] a_hold;
    logic [31:0] q_hold;

    logic [31:0] mul_result;
    logic        mul_busy;
    logic        mul_done;
    logic        mul_start;

    logic [32:0] a_ext;
    logic [32:0] t_ext;
    logic [32:0] q_ext;

    logic [32:0] sum_ext;
    logic [32:0] reduced_sum_ext;
    logic [32:0] difference_ext;

    /*
     * Accept a new multiplication only when the complete butterfly
     * is idle. modmul_core samples omega, b, and q on this pulse.
     */
    assign mul_start = start && !busy;

    modmul_core multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (mul_start),

        .a       (omega),
        .b       (b),
        .q       (q),

        .result  (mul_result),
        .busy    (mul_busy),
        .done    (mul_done)
    );

    assign a_ext = {1'b0, a_hold};
    assign t_ext = {1'b0, mul_result};
    assign q_ext = {1'b0, q_hold};

    /*
     * out_a = (a + t) mod q
     *
     * Since a < q and t < q, a + t < 2q, so at most one
     * subtraction is required.
     */
    assign sum_ext = a_ext + t_ext;

    assign reduced_sum_ext =
        (sum_ext >= q_ext)
            ? sum_ext - q_ext
            : sum_ext;

    /*
     * out_b = (a - t) mod q
     *
     * If a < t, add q before subtracting. The resulting value
     * is always in [0, q).
     */
    assign difference_ext =
        (a_ext >= t_ext)
            ? a_ext - t_ext
            : (a_ext + q_ext) - t_ext;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            a_hold <= 32'd0;
            q_hold <= 32'd0;

            out_a <= 32'd0;
            out_b <= 32'd0;

            busy <= 1'b0;
            done <= 1'b0;
        end
        else
        begin
            // Completion is a one-clock pulse.
            done <= 1'b0;

            if (start && !busy)
            begin
                a_hold <= a;
                q_hold <= q;

                out_a <= 32'd0;
                out_b <= 32'd0;

                busy <= 1'b1;
            end
            else if (mul_done && busy)
            begin
                /*
                 * Modulus zero is not meaningful for an NTT, but
                 * define it consistently as an immediate zero result.
                 */
                if (q_hold == 32'd0)
                begin
                    out_a <= 32'd0;
                    out_b <= 32'd0;
                end
                else
                begin
                    out_a <= reduced_sum_ext[31:0];
                    out_b <= difference_ext[31:0];
                end

                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end

endmodule
