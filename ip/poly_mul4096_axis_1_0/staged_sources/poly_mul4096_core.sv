`timescale 1ns/1ps

/*
 * Complete N=4096 negacyclic polynomial multiplier.
 *
 *     C(X) = A(X) * B(X) mod (X^4096 + 1, q)
 *
 * Architecture:
 *
 *   1. Forward-transform A and B in parallel.
 *   2. Copy both transformed vectors into the pointwise engine.
 *   3. Multiply all 4096 evaluation-domain coefficients.
 *   4. Copy the pointwise vector into the inverse engine.
 *   5. Run the complete inverse negacyclic transform.
 *
 * The two forward engines are deliberately concurrent. This removes
 * one complete 626691-cycle transform from product latency.
 *
 * External coefficient loading and result reads are accepted only
 * while the complete product controller is idle.
 */
module poly_mul4096_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_a_we,
    input  logic [11:0] load_a_addr,
    input  logic [31:0] load_a_data,

    input  logic        load_b_we,
    input  logic [11:0] load_b_addr,
    input  logic [31:0] load_b_data,

    input  logic [11:0] read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [16:0] multiplication_count,

    output logic [31:0] forward_cycles,
    output logic [31:0] pointwise_cycles,
    output logic [31:0] inverse_cycles
);

    localparam integer TOTAL_COEFFICIENTS =
        4096;

    localparam logic [16:0] TOTAL_MODULAR_MULTIPLICATIONS =
        17'd90112;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_FORWARD_START,
        STATE_FORWARD_WAIT,
        STATE_FORWARD_TRANSFER_READ_ISSUE,
        STATE_FORWARD_TRANSFER_READ_CAPTURE,
        STATE_FORWARD_TRANSFER_WRITE,
        STATE_POINTWISE_START,
        STATE_POINTWISE_WAIT,
        STATE_POINTWISE_TRANSFER_READ_ISSUE,
        STATE_POINTWISE_TRANSFER_READ_CAPTURE,
        STATE_POINTWISE_TRANSFER_WRITE,
        STATE_INVERSE_START,
        STATE_INVERSE_WAIT
    } state_t;

    state_t state;

    logic forward_start;

    logic forward_a_load_we;
    logic forward_b_load_we;

    logic [11:0] forward_read_addr;

    logic [31:0] forward_a_read_data;
    logic [31:0] forward_b_read_data;

    logic forward_a_busy;
    logic forward_a_done;

    logic forward_b_busy;
    logic forward_b_done;

    logic [31:0] forward_a_cycles;
    logic [31:0] forward_b_cycles;

    logic [12:0] forward_a_preprocessing_count;
    logic [12:0] forward_b_preprocessing_count;

    logic [14:0] forward_a_butterfly_count;
    logic [14:0] forward_b_butterfly_count;

    logic pointwise_start;

    logic pointwise_load_a_we;
    logic pointwise_load_b_we;

    logic [11:0] pointwise_load_addr;
    logic [31:0] pointwise_load_a_data;
    logic [31:0] pointwise_load_b_data;

    logic [11:0] pointwise_read_addr;
    logic [31:0] pointwise_read_data;

    logic pointwise_busy;
    logic pointwise_done;

    logic [31:0] pointwise_cycles_internal;
    logic [12:0] pointwise_multiplication_count;

    logic inverse_start;

    logic inverse_load_we;
    logic [11:0] inverse_load_addr;
    logic [31:0] inverse_load_data;

    logic [31:0] inverse_read_data;

    logic inverse_busy;
    logic inverse_done;

    logic [31:0] inverse_cycles_internal;
    logic [12:0] inverse_preparation_count;
    logic [14:0] inverse_butterfly_count;
    logic [12:0] inverse_postprocessing_count;

    logic [11:0] transfer_index;

    logic [31:0] captured_forward_a;
    logic [31:0] captured_forward_b;
    logic [31:0] captured_pointwise;

    assign forward_start =
        state == STATE_FORWARD_START;

    assign forward_a_load_we =
        !busy
        && load_a_we;

    assign forward_b_load_we =
        !busy
        && load_b_we;

    assign forward_read_addr =
        transfer_index;

    assign pointwise_start =
        state == STATE_POINTWISE_START;

    assign pointwise_load_a_we =
        state == STATE_FORWARD_TRANSFER_WRITE;

    assign pointwise_load_b_we =
        state == STATE_FORWARD_TRANSFER_WRITE;

    assign pointwise_load_addr =
        transfer_index;

    assign pointwise_load_a_data =
        captured_forward_a;

    assign pointwise_load_b_data =
        captured_forward_b;

    assign pointwise_read_addr =
        transfer_index;

    assign inverse_start =
        state == STATE_INVERSE_START;

    assign inverse_load_we =
        state == STATE_POINTWISE_TRANSFER_WRITE;

    assign inverse_load_addr =
        transfer_index;

    assign inverse_load_data =
        captured_pointwise;

    assign read_data =
        inverse_read_data;

    assign forward_cycles =
        forward_a_cycles;

    assign pointwise_cycles =
        pointwise_cycles_internal;

    assign inverse_cycles =
        inverse_cycles_internal;

    forward_ntt4096_core forward_a (
        .clk                 (clk),
        .reset_n             (reset_n),
        .start               (forward_start),

        .load_we             (forward_a_load_we),
        .load_addr           (load_a_addr),
        .load_data           (load_a_data),

        .read_addr           (forward_read_addr),
        .read_data           (forward_a_read_data),

        .busy                (forward_a_busy),
        .done                (forward_a_done),

        .cycles              (forward_a_cycles),
        .preprocessing_count (forward_a_preprocessing_count),
        .butterfly_count     (forward_a_butterfly_count)
    );

    forward_ntt4096_core forward_b (
        .clk                 (clk),
        .reset_n             (reset_n),
        .start               (forward_start),

        .load_we             (forward_b_load_we),
        .load_addr           (load_b_addr),
        .load_data           (load_b_data),

        .read_addr           (forward_read_addr),
        .read_data           (forward_b_read_data),

        .busy                (forward_b_busy),
        .done                (forward_b_done),

        .cycles              (forward_b_cycles),
        .preprocessing_count (forward_b_preprocessing_count),
        .butterfly_count     (forward_b_butterfly_count)
    );

    pointwise_mul4096_core pointwise (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (pointwise_start),

        .load_a_we            (pointwise_load_a_we),
        .load_a_addr          (pointwise_load_addr),
        .load_a_data          (pointwise_load_a_data),

        .load_b_we            (pointwise_load_b_we),
        .load_b_addr          (pointwise_load_addr),
        .load_b_data          (pointwise_load_b_data),

        .read_addr            (pointwise_read_addr),
        .read_data            (pointwise_read_data),

        .busy                 (pointwise_busy),
        .done                 (pointwise_done),

        .cycles               (pointwise_cycles_internal),
        .multiplication_count (pointwise_multiplication_count)
    );

    inverse_ntt4096_core inverse (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (inverse_start),

        .load_we              (inverse_load_we),
        .load_addr            (inverse_load_addr),
        .load_data            (inverse_load_data),

        .read_addr            (read_addr),
        .read_data            (inverse_read_data),

        .busy                 (inverse_busy),
        .done                 (inverse_done),

        .cycles               (inverse_cycles_internal),
        .preparation_count    (inverse_preparation_count),
        .butterfly_count      (inverse_butterfly_count),
        .postprocessing_count (inverse_postprocessing_count)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            multiplication_count <=
                17'd0;

            transfer_index <=
                12'd0;

            captured_forward_a <=
                32'd0;

            captured_forward_b <=
                32'd0;

            captured_pointwise <=
                32'd0;
        end
        else
        begin
            done <=
                1'b0;

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start)
                    begin
                        state <=
                            STATE_FORWARD_START;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        multiplication_count <=
                            17'd0;

                        transfer_index <=
                            12'd0;
                    end
                end

                STATE_FORWARD_START:
                begin
                    state <=
                        STATE_FORWARD_WAIT;
                end

                STATE_FORWARD_WAIT:
                begin
                    if (
                        forward_a_done
                        && forward_b_done
                    )
                    begin
                        transfer_index <=
                            12'd0;

                        state <=
                            STATE_FORWARD_TRANSFER_READ_ISSUE;
                    end
                end

                STATE_FORWARD_TRANSFER_READ_ISSUE:
                begin
                    state <=
                        STATE_FORWARD_TRANSFER_READ_CAPTURE;
                end

                STATE_FORWARD_TRANSFER_READ_CAPTURE:
                begin
                    captured_forward_a <=
                        forward_a_read_data;

                    captured_forward_b <=
                        forward_b_read_data;

                    state <=
                        STATE_FORWARD_TRANSFER_WRITE;
                end

                STATE_FORWARD_TRANSFER_WRITE:
                begin
                    if (
                        transfer_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_POINTWISE_START;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_FORWARD_TRANSFER_READ_ISSUE;
                    end
                end

                STATE_POINTWISE_START:
                begin
                    state <=
                        STATE_POINTWISE_WAIT;
                end

                STATE_POINTWISE_WAIT:
                begin
                    if (pointwise_done)
                    begin
                        transfer_index <=
                            12'd0;

                        state <=
                            STATE_POINTWISE_TRANSFER_READ_ISSUE;
                    end
                end

                STATE_POINTWISE_TRANSFER_READ_ISSUE:
                begin
                    state <=
                        STATE_POINTWISE_TRANSFER_READ_CAPTURE;
                end

                STATE_POINTWISE_TRANSFER_READ_CAPTURE:
                begin
                    captured_pointwise <=
                        pointwise_read_data;

                    state <=
                        STATE_POINTWISE_TRANSFER_WRITE;
                end

                STATE_POINTWISE_TRANSFER_WRITE:
                begin
                    if (
                        transfer_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_INVERSE_START;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_POINTWISE_TRANSFER_READ_ISSUE;
                    end
                end

                STATE_INVERSE_START:
                begin
                    state <=
                        STATE_INVERSE_WAIT;
                end

                STATE_INVERSE_WAIT:
                begin
                    if (inverse_done)
                    begin
                        state <=
                            STATE_IDLE;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;

                        multiplication_count <=
                            TOTAL_MODULAR_MULTIPLICATIONS;
                    end
                end

                default:
                begin
                    state <=
                        STATE_IDLE;

                    busy <=
                        1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            state == STATE_FORWARD_START
            && (
                forward_a_busy
                || forward_b_busy
            )
        )
        begin
            $display(
                "ERROR: N=4096 forward start attempted while a forward engine is busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_FORWARD_WAIT
            && (
                forward_a_done
                ^ forward_b_done
            )
        )
        begin
            $display(
                "ERROR: parallel N=4096 forward engines completed on different clocks"
            );

            $fatal(1);
        end

        if (
            state == STATE_POINTWISE_START
            && pointwise_busy
        )
        begin
            $display(
                "ERROR: N=4096 pointwise start attempted while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_INVERSE_START
            && inverse_busy
        )
        begin
            $display(
                "ERROR: N=4096 inverse start attempted while busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
