`timescale 1ns/1ps

/*
 * Fully pipelined Barrett modular multiplier for moduli below 2^30.
 *
 * Preconditions:
 *
 *     0 < q < 2^30
 *     a < q
 *     b < q
 *     mu = floor(2^60 / q)
 *
 * The 60x31 reciprocal multiplication is explicitly decomposed into
 * eight 15x16-or-smaller products. Each partial product fits within
 * one DSP48E1 multiplier without a PCIN cascade.
 *
 * Pipeline:
 *
 *     P0 capture input
 *     P1 z = a*b
 *     P2 eight reciprocal partial products
 *     P3 first reciprocal adder level
 *     P4 form two 30x31 half-products
 *     P5 combine the half-products into z*mu
 *     P6 extract qhat
 *     P7 qhat*q
 *     P8 provisional remainder
 *     P9 correction/output
 *
 * Initiation interval: 1 clock
 * Input-to-output latency: 9 clocks
 */
module modmul_barrett60_pipeline_chunked_core (
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
     * P0: input capture.
     */
    logic        valid_stage0;
    logic [31:0] a_stage0;
    logic [31:0] b_stage0;
    logic [31:0] q_stage0;
    logic [30:0] mu_stage0;

    /*
     * P1: input product.
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
     * Decompose:
     *
     *     z_low  = zl0 + 2^15 zl1
     *     z_high = zh0 + 2^15 zh1
     *     mu     = m0  + 2^16 m1
     *
     * Each 30x31 half-product is:
     *
     *       x0*m0
     *     + 2^15 x1*m0
     *     + 2^16 x0*m1
     *     + 2^31 x1*m1
     */

    /*
     * P2: eight independent partial products.
     */
    logic        valid_stage2;

    logic [30:0] low_p00_stage2;
    logic [30:0] low_p10_stage2;
    logic [29:0] low_p01_stage2;
    logic [29:0] low_p11_stage2;

    logic [30:0] high_p00_stage2;
    logic [30:0] high_p10_stage2;
    logic [29:0] high_p01_stage2;
    logic [29:0] high_p11_stage2;

    logic [63:0] product_delay_stage2;
    logic [31:0] q_stage2;

    (* use_dsp = "yes" *)
    logic [30:0] low_p00_comb;

    (* use_dsp = "yes" *)
    logic [30:0] low_p10_comb;

    (* use_dsp = "yes" *)
    logic [29:0] low_p01_comb;

    (* use_dsp = "yes" *)
    logic [29:0] low_p11_comb;

    (* use_dsp = "yes" *)
    logic [30:0] high_p00_comb;

    (* use_dsp = "yes" *)
    logic [30:0] high_p10_comb;

    (* use_dsp = "yes" *)
    logic [29:0] high_p01_comb;

    (* use_dsp = "yes" *)
    logic [29:0] high_p11_comb;

    assign low_p00_comb =
        product_stage1[14:0]
        * mu_stage1[15:0];

    assign low_p10_comb =
        product_stage1[29:15]
        * mu_stage1[15:0];

    assign low_p01_comb =
        product_stage1[14:0]
        * mu_stage1[30:16];

    assign low_p11_comb =
        product_stage1[29:15]
        * mu_stage1[30:16];

    assign high_p00_comb =
        product_stage1[44:30]
        * mu_stage1[15:0];

    assign high_p10_comb =
        product_stage1[59:45]
        * mu_stage1[15:0];

    assign high_p01_comb =
        product_stage1[44:30]
        * mu_stage1[30:16];

    assign high_p11_comb =
        product_stage1[59:45]
        * mu_stage1[30:16];

    /*
     * P3: first reciprocal adder level.
     */
    logic        valid_stage3;

    logic [60:0] low_sum0_stage3;
    logic [60:0] low_sum1_stage3;
    logic [60:0] high_sum0_stage3;
    logic [60:0] high_sum1_stage3;

    logic [63:0] product_delay_stage3;
    logic [31:0] q_stage3;

    logic [60:0] low_sum0_comb;
    logic [60:0] low_sum1_comb;
    logic [60:0] high_sum0_comb;
    logic [60:0] high_sum1_comb;

    assign low_sum0_comb =
        {30'd0, low_p00_stage2}
        + (
            {30'd0, low_p10_stage2}
            << 15
        );

    assign low_sum1_comb =
        (
            {31'd0, low_p01_stage2}
            << 16
        )
        + (
            {31'd0, low_p11_stage2}
            << 31
        );

    assign high_sum0_comb =
        {30'd0, high_p00_stage2}
        + (
            {30'd0, high_p10_stage2}
            << 15
        );

    assign high_sum1_comb =
        (
            {31'd0, high_p01_stage2}
            << 16
        )
        + (
            {31'd0, high_p11_stage2}
            << 31
        );

    /*
     * P4: finish each 30x31 half-product.
     */
    logic        valid_stage4;
    logic [60:0] reciprocal_low_stage4;
    logic [60:0] reciprocal_high_stage4;
    logic [63:0] product_delay_stage4;
    logic [31:0] q_stage4;

    logic [60:0] reciprocal_low_comb;
    logic [60:0] reciprocal_high_comb;

    assign reciprocal_low_comb =
        low_sum0_stage3
        + low_sum1_stage3;

    assign reciprocal_high_comb =
        high_sum0_stage3
        + high_sum1_stage3;

    /*
     * P5: combine:
     *
     *     z*mu =
     *         reciprocal_low
     *         + 2^30 reciprocal_high
     */
    logic        valid_stage5;
    logic [90:0] reciprocal_product_stage5;
    logic [63:0] product_delay_stage5;
    logic [31:0] q_stage5;

    logic [90:0] reciprocal_product_combined;

    assign reciprocal_product_combined =
        {30'd0, reciprocal_low_stage4}
        + (
            {30'd0, reciprocal_high_stage4}
            << 30
        );

    /*
     * P6: quotient estimate.
     */
    logic        valid_stage6;
    logic [30:0] quotient_stage6;
    logic [63:0] product_delay_stage6;
    logic [31:0] q_stage6;

    /*
     * P7: quotient times modulus.
     */
    logic        valid_stage7;
    logic [62:0] quotient_product_stage7;
    logic [63:0] product_delay_stage7;
    logic [31:0] q_stage7;

    (* use_dsp = "yes" *)
    logic [62:0] quotient_product_comb;

    assign quotient_product_comb =
        quotient_stage6
        * q_stage6;

    /*
     * P8: provisional remainder.
     */
    logic        valid_stage8;
    logic [63:0] remainder_stage8;
    logic [31:0] q_stage8;

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
            valid_stage6 <= 1'b0;
            valid_stage7 <= 1'b0;
            valid_stage8 <= 1'b0;
            output_valid <= 1'b0;

            a_stage0 <= 32'd0;
            b_stage0 <= 32'd0;
            q_stage0 <= 32'd0;
            mu_stage0 <= 31'd0;

            product_stage1 <= 64'd0;
            q_stage1 <= 32'd0;
            mu_stage1 <= 31'd0;

            low_p00_stage2 <= 31'd0;
            low_p10_stage2 <= 31'd0;
            low_p01_stage2 <= 30'd0;
            low_p11_stage2 <= 30'd0;

            high_p00_stage2 <= 31'd0;
            high_p10_stage2 <= 31'd0;
            high_p01_stage2 <= 30'd0;
            high_p11_stage2 <= 30'd0;

            product_delay_stage2 <= 64'd0;
            q_stage2 <= 32'd0;

            low_sum0_stage3 <= 61'd0;
            low_sum1_stage3 <= 61'd0;
            high_sum0_stage3 <= 61'd0;
            high_sum1_stage3 <= 61'd0;

            product_delay_stage3 <= 64'd0;
            q_stage3 <= 32'd0;

            reciprocal_low_stage4 <= 61'd0;
            reciprocal_high_stage4 <= 61'd0;
            product_delay_stage4 <= 64'd0;
            q_stage4 <= 32'd0;

            reciprocal_product_stage5 <= 91'd0;
            product_delay_stage5 <= 64'd0;
            q_stage5 <= 32'd0;

            quotient_stage6 <= 31'd0;
            product_delay_stage6 <= 64'd0;
            q_stage6 <= 32'd0;

            quotient_product_stage7 <= 63'd0;
            product_delay_stage7 <= 64'd0;
            q_stage7 <= 32'd0;

            remainder_stage8 <= 64'd0;
            q_stage8 <= 32'd0;

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

            low_p00_stage2 <=
                low_p00_comb;

            low_p10_stage2 <=
                low_p10_comb;

            low_p01_stage2 <=
                low_p01_comb;

            low_p11_stage2 <=
                low_p11_comb;

            high_p00_stage2 <=
                high_p00_comb;

            high_p10_stage2 <=
                high_p10_comb;

            high_p01_stage2 <=
                high_p01_comb;

            high_p11_stage2 <=
                high_p11_comb;

            product_delay_stage2 <=
                product_stage1;

            q_stage2 <=
                q_stage1;

            /*
             * P3
             */
            valid_stage3 <=
                valid_stage2;

            low_sum0_stage3 <=
                low_sum0_comb;

            low_sum1_stage3 <=
                low_sum1_comb;

            high_sum0_stage3 <=
                high_sum0_comb;

            high_sum1_stage3 <=
                high_sum1_comb;

            product_delay_stage3 <=
                product_delay_stage2;

            q_stage3 <=
                q_stage2;

            /*
             * P4
             */
            valid_stage4 <=
                valid_stage3;

            reciprocal_low_stage4 <=
                reciprocal_low_comb;

            reciprocal_high_stage4 <=
                reciprocal_high_comb;

            product_delay_stage4 <=
                product_delay_stage3;

            q_stage4 <=
                q_stage3;

            /*
             * P5
             */
            valid_stage5 <=
                valid_stage4;

            reciprocal_product_stage5 <=
                reciprocal_product_combined;

            product_delay_stage5 <=
                product_delay_stage4;

            q_stage5 <=
                q_stage4;

            /*
             * P6
             */
            valid_stage6 <=
                valid_stage5;

            quotient_stage6 <=
                reciprocal_product_stage5[90:60];

            product_delay_stage6 <=
                product_delay_stage5;

            q_stage6 <=
                q_stage5;

            /*
             * P7
             */
            valid_stage7 <=
                valid_stage6;

            quotient_product_stage7 <=
                quotient_product_comb;

            product_delay_stage7 <=
                product_delay_stage6;

            q_stage7 <=
                q_stage6;

            /*
             * P8
             */
            valid_stage8 <=
                valid_stage7;

            remainder_stage8 <=
                product_delay_stage7
                - {1'b0, quotient_product_stage7};

            q_stage8 <=
                q_stage7;

            /*
             * P9
             */
            output_valid <=
                valid_stage8;

            if (valid_stage8)
            begin
                result <=
                    remainder_stage8 >= {32'd0, q_stage8}
                        ? remainder_stage8[31:0] - q_stage8
                        : remainder_stage8[31:0];
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
                $display(
                    "ERROR: Barrett multiplier received q=0"
                );

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
            && valid_stage6
            && quotient_stage6[30]
        )
        begin
            $display(
                "ERROR: quotient estimate exceeded 30 bits: %h",
                quotient_stage6
            );

            $fatal(1);
        end

        if (
            reset_n
            && valid_stage8
            && remainder_stage8 >= ({32'd0, q_stage8} << 1)
        )
        begin
            $display(
                "ERROR: provisional remainder exceeded 2q: r=%0d q=%0d",
                remainder_stage8,
                q_stage8
            );

            $fatal(1);
        end
    end

`endif

endmodule
