`timescale 1ns/1ps

/*
 * Fully pipelined modular multiplier for moduli below 2^30.
 *
 * Preconditions:
 *
 *     0 < q < 2^30
 *     a < q
 *     b < q
 *     mu = floor(2^60 / q)
 *
 * Barrett reduction:
 *
 *     z    = a * b
 *     qhat = floor(z * mu / 2^60)
 *     r    = z - qhat * q
 *
 * Under the stated bounds:
 *
 *     floor(z / q) - 1 <= qhat <= floor(z / q)
 *     0 <= r < 2q
 *
 * Therefore one final conditional subtraction produces z mod q.
 *
 * Pipeline:
 *
 *     P0 capture input
 *     P1 z = a*b
 *     P2 reciprocal product = z*mu
 *     P3 extract qhat
 *     P4 qhat*q
 *     P5 remainder
 *     P6 correction/output
 *
 * Initiation interval: 1 clock
 * Input-to-output latency: 6 clocks
 */
module modmul_barrett60_pipeline_core (
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

    /*
     * P0: input registers.
     */
    logic        valid_stage0;
    logic [31:0] a_stage0;
    logic [31:0] b_stage0;
    logic [31:0] q_stage0;
    logic [30:0] mu_stage0;

    /*
     * P1: 32 x 32 product.
     *
     * The product is below 2^60 under the input constraints.
     */
    logic        valid_stage1;
    logic [63:0] product_stage1;
    logic [31:0] q_stage1;
    logic [30:0] mu_stage1;

    (* use_dsp = "yes" *)
    logic [63:0] product_comb;

    assign product_comb =
        a_stage0 * b_stage0;

    /*
     * P2: 60 x 31 reciprocal product.
     */
    logic        valid_stage2;
    logic [90:0] reciprocal_product_stage2;
    logic [63:0] product_delay_stage2;
    logic [31:0] q_stage2;

    (* use_dsp = "yes" *)
    logic [90:0] reciprocal_product_comb;

    assign reciprocal_product_comb =
        product_stage1[59:0] * mu_stage1;

    /*
     * P3: quotient estimate.
     */
    logic        valid_stage3;
    logic [30:0] quotient_stage3;
    logic [63:0] product_delay_stage3;
    logic [31:0] q_stage3;

    /*
     * P4: quotient times modulus.
     */
    logic        valid_stage4;
    logic [62:0] quotient_product_stage4;
    logic [63:0] product_delay_stage4;
    logic [31:0] q_stage4;

    (* use_dsp = "yes" *)
    logic [62:0] quotient_product_comb;

    assign quotient_product_comb =
        quotient_stage3 * q_stage3;

    /*
     * P5: provisional remainder.
     */
    logic        valid_stage5;
    logic [63:0] remainder_stage5;
    logic [31:0] q_stage5;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            valid_stage0 <= 1'b0;
            valid_stage1 <= 1'b0;
            valid_stage2 <= 1'b0;
            valid_stage3 <= 1'b0;
            valid_stage4 <= 1'b0;
            valid_stage5 <= 1'b0;
            output_valid <= 1'b0;

            a_stage0 <= 32'd0;
            b_stage0 <= 32'd0;
            q_stage0 <= 32'd0;
            mu_stage0 <= 31'd0;

            product_stage1 <= 64'd0;
            q_stage1 <= 32'd0;
            mu_stage1 <= 31'd0;

            reciprocal_product_stage2 <= 91'd0;
            product_delay_stage2 <= 64'd0;
            q_stage2 <= 32'd0;

            quotient_stage3 <= 31'd0;
            product_delay_stage3 <= 64'd0;
            q_stage3 <= 32'd0;

            quotient_product_stage4 <= 63'd0;
            product_delay_stage4 <= 64'd0;
            q_stage4 <= 32'd0;

            remainder_stage5 <= 64'd0;
            q_stage5 <= 32'd0;

            result <= 32'd0;
        end
        else
        begin
            /*
             * P0
             */
            valid_stage0 <=
                input_valid;

            if (input_valid)
            begin
                a_stage0 <=
                    a;

                b_stage0 <=
                    b;

                q_stage0 <=
                    q;

                mu_stage0 <=
                    mu;
            end

            /*
             * P1
             */
            valid_stage1 <=
                valid_stage0;

            product_stage1 <=
                product_comb;

            q_stage1 <=
                q_stage0;

            mu_stage1 <=
                mu_stage0;

            /*
             * P2
             */
            valid_stage2 <=
                valid_stage1;

            reciprocal_product_stage2 <=
                reciprocal_product_comb;

            product_delay_stage2 <=
                product_stage1;

            q_stage2 <=
                q_stage1;

            /*
             * P3
             */
            valid_stage3 <=
                valid_stage2;

            quotient_stage3 <=
                reciprocal_product_stage2[90:60];

            product_delay_stage3 <=
                product_delay_stage2;

            q_stage3 <=
                q_stage2;

            /*
             * P4
             */
            valid_stage4 <=
                valid_stage3;

            quotient_product_stage4 <=
                quotient_product_comb;

            product_delay_stage4 <=
                product_delay_stage3;

            q_stage4 <=
                q_stage3;

            /*
             * P5
             */
            valid_stage5 <=
                valid_stage4;

            remainder_stage5 <=
                product_delay_stage4
                - {1'b0, quotient_product_stage4};

            q_stage5 <=
                q_stage4;

            /*
             * P6
             */
            output_valid <=
                valid_stage5;

            if (valid_stage5)
            begin
                result <=
                    remainder_stage5 >= {32'd0, q_stage5}
                        ? remainder_stage5[31:0] - q_stage5
                        : remainder_stage5[31:0];
            end
        end
    end

`ifndef SYNTHESIS

    localparam logic [63:0] BARRETT_SCALE =
        64'h1000000000000000;

    always @(posedge clk)
    begin
        if (reset_n && input_valid)
        begin
            if (q == 32'd0)
            begin
                $display("ERROR: Barrett multiplier received q=0");
                $fatal(1);
            end

            if (q[31:30] != 2'b00)
            begin
                $display(
                    "ERROR: Barrett multiplier requires q < 2^30; q=%0d",
                    q
                );
                $fatal(1);
            end

            if (a >= q || b >= q)
            begin
                $display(
                    "ERROR: noncanonical input a=%0d b=%0d q=%0d",
                    a,
                    b,
                    q
                );
                $fatal(1);
            end

            if (mu != BARRETT_SCALE / q)
            begin
                $display(
                    "ERROR: incorrect reciprocal q=%0d mu=%0d expected=%0d",
                    q,
                    mu,
                    BARRETT_SCALE / q
                );
                $fatal(1);
            end
        end

        if (
            reset_n
            && valid_stage1
            && product_stage1[63:60] != 4'd0
        )
        begin
            $display(
                "ERROR: product exceeded 60-bit Barrett bound: %h",
                product_stage1
            );
            $fatal(1);
        end

        if (
            reset_n
            && valid_stage5
            && remainder_stage5 >= ({32'd0, q_stage5} << 1)
        )
        begin
            $display(
                "ERROR: provisional remainder exceeded 2q: r=%0d q=%0d",
                remainder_stage5,
                q_stage5
            );
            $fatal(1);
        end
    end

`endif

endmodule
