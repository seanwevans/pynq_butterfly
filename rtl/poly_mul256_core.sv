`timescale 1ns/1ps

/*
 * Complete BRAM-backed N=256 negacyclic polynomial multiplier.
 *
 * Computes:
 *
 *     C(X) = A(X)B(X) mod (X^256 + 1, q)
 *
 * where:
 *
 *     q = 1073692673
 *
 * Pipeline:
 *
 *     A -> forward negacyclic NTT
 *     B -> forward negacyclic NTT
 *       -> pointwise modular multiplication
 *       -> inverse negacyclic NTT
 *       -> C
 *
 * One forward engine is reused for A and B.
 */
module poly_mul256_core #(
    parameter FORWARD_TWIST_INIT_FILE =
        "../tests/fixtures/ntt_n256/twist_factors.mem",

    parameter FORWARD_TWIDDLE_INIT_FILE =
        "../tests/fixtures/ntt_n256/forward_twiddles.mem",

    parameter INVERSE_TWIDDLE_INIT_FILE =
        "../tests/fixtures/ntt_n256/inverse_twiddles.mem",

    parameter INVERSE_SCALE_INIT_FILE =
        "../tests/fixtures/ntt_n256/inverse_scale_factors.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    /*
     * Natural-order polynomial loading interface.
     *
     * load_bank = 0 selects polynomial A.
     * load_bank = 1 selects polynomial B.
     *
     * Writes are accepted only while idle.
     */
    input  logic        load_we,
    input  logic        load_bank,
    input  logic [7:0]  load_addr,
    input  logic [31:0] load_data,

    /*
     * Natural-order result interface.
     *
     * Reads are synchronous with one-clock latency.
     */
    input  logic [7:0]  read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [12:0] modular_multiplication_count
);

    typedef enum logic [4:0] {
        STATE_IDLE,

        STATE_SOURCE_A_READ,
        STATE_SOURCE_A_CAPTURE,
        STATE_FORWARD_A_LOAD,

        STATE_FORWARD_A_START,
        STATE_FORWARD_A_WAIT,

        STATE_FORWARD_A_READ,
        STATE_FORWARD_A_CAPTURE,
        STATE_POINTWISE_A_LOAD,

        STATE_SOURCE_B_READ,
        STATE_SOURCE_B_CAPTURE,
        STATE_FORWARD_B_LOAD,

        STATE_FORWARD_B_START,
        STATE_FORWARD_B_WAIT,

        STATE_FORWARD_B_READ,
        STATE_FORWARD_B_CAPTURE,
        STATE_POINTWISE_B_LOAD,

        STATE_POINTWISE_START,
        STATE_POINTWISE_WAIT,

        STATE_POINTWISE_READ,
        STATE_POINTWISE_CAPTURE,
        STATE_INVERSE_LOAD,

        STATE_INVERSE_START,
        STATE_INVERSE_WAIT
    } state_t;

    state_t state;

    logic [7:0] transfer_index;
    logic [31:0] transfer_value;

    /*
     * Original source-polynomial BRAMs.
     */
    logic        source_a_enable;
    logic        source_a_write_enable;
    logic [7:0]  source_a_address;
    logic [31:0] source_a_write_data;
    logic [31:0] source_a_read_data;

    logic        source_b_enable;
    logic        source_b_write_enable;
    logic [7:0]  source_b_address;
    logic [31:0] source_b_write_data;
    logic [31:0] source_b_read_data;

    logic [31:0] source_a_unused_read_data;
    logic [31:0] source_b_unused_read_data;

    /*
     * Reusable forward NTT engine.
     */
    logic        forward_start;
    logic        forward_load_we;
    logic [7:0]  forward_load_addr;
    logic [31:0] forward_load_data;

    logic [7:0]  forward_read_addr;
    logic [31:0] forward_read_data;

    logic        forward_busy;
    logic        forward_done;

    logic [31:0] forward_cycles;
    logic [8:0]  forward_preprocess_count;
    logic [10:0] forward_butterfly_count;

    /*
     * Pointwise multiplier.
     */
    logic        pointwise_start;

    logic        pointwise_load_we;
    logic        pointwise_load_bank;
    logic [7:0]  pointwise_load_addr;
    logic [31:0] pointwise_load_data;

    logic [7:0]  pointwise_read_addr;
    logic [31:0] pointwise_read_data;

    logic        pointwise_busy;
    logic        pointwise_done;

    logic [31:0] pointwise_cycles;
    logic [8:0]  pointwise_count;

    /*
     * Inverse NTT engine.
     */
    logic        inverse_start;

    logic        inverse_load_we;
    logic [7:0]  inverse_load_addr;
    logic [31:0] inverse_load_data;

    logic [31:0] inverse_read_data;

    logic        inverse_busy;
    logic        inverse_done;

    logic [31:0] inverse_cycles;
    logic [8:0]  inverse_postprocess_count;
    logic [10:0] inverse_butterfly_count;

    /*
     * Forward-engine command signals.
     */
    assign forward_start =
        (state == STATE_FORWARD_A_START) ||
        (state == STATE_FORWARD_B_START);

    assign forward_load_we =
        (state == STATE_FORWARD_A_LOAD) ||
        (state == STATE_FORWARD_B_LOAD);

    assign forward_load_addr =
        transfer_index;

    assign forward_load_data =
        transfer_value;

    assign forward_read_addr =
        transfer_index;

    /*
     * Pointwise-engine command signals.
     */
    assign pointwise_start =
        state == STATE_POINTWISE_START;

    assign pointwise_load_we =
        (state == STATE_POINTWISE_A_LOAD) ||
        (state == STATE_POINTWISE_B_LOAD);

    assign pointwise_load_bank =
        state == STATE_POINTWISE_B_LOAD;

    assign pointwise_load_addr =
        transfer_index;

    assign pointwise_load_data =
        transfer_value;

    assign pointwise_read_addr =
        transfer_index;

    /*
     * Inverse-engine command signals.
     */
    assign inverse_start =
        state == STATE_INVERSE_START;

    assign inverse_load_we =
        state == STATE_INVERSE_LOAD;

    assign inverse_load_addr =
        transfer_index;

    assign inverse_load_data =
        transfer_value;

    assign read_data =
        inverse_read_data;

    /*
     * Source-polynomial memory arbitration.
     */
    always @*
    begin
        source_a_enable       = 1'b0;
        source_a_write_enable = 1'b0;
        source_a_address      = 8'd0;
        source_a_write_data   = 32'd0;

        source_b_enable       = 1'b0;
        source_b_write_enable = 1'b0;
        source_b_address      = 8'd0;
        source_b_write_data   = 32'd0;

        if (!busy)
        begin
            if (load_we && !load_bank)
            begin
                source_a_enable =
                    1'b1;

                source_a_write_enable =
                    1'b1;

                source_a_address =
                    load_addr;

                source_a_write_data =
                    load_data;
            end

            if (load_we && load_bank)
            begin
                source_b_enable =
                    1'b1;

                source_b_write_enable =
                    1'b1;

                source_b_address =
                    load_addr;

                source_b_write_data =
                    load_data;
            end
        end
        else
        begin
            if (state == STATE_SOURCE_A_READ)
            begin
                source_a_enable =
                    1'b1;

                source_a_address =
                    transfer_index;
            end

            if (state == STATE_SOURCE_B_READ)
            begin
                source_b_enable =
                    1'b1;

                source_b_address =
                    transfer_index;
            end
        end
    end

    ntt256_coeff_bram polynomial_a_memory (
        .clk                 (clk),

        .port_a_enable       (source_a_enable),
        .port_a_write_enable (source_a_write_enable),
        .port_a_address      (source_a_address),
        .port_a_write_data   (source_a_write_data),
        .port_a_read_data    (source_a_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (8'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (source_a_unused_read_data)
    );

    ntt256_coeff_bram polynomial_b_memory (
        .clk                 (clk),

        .port_a_enable       (source_b_enable),
        .port_a_write_enable (source_b_write_enable),
        .port_a_address      (source_b_address),
        .port_a_write_data   (source_b_write_data),
        .port_a_read_data    (source_b_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (8'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (source_b_unused_read_data)
    );

    forward_ntt256_core #(
        .TWIST_INIT_FILE(
            FORWARD_TWIST_INIT_FILE
        ),

        .TWIDDLE_INIT_FILE(
            FORWARD_TWIDDLE_INIT_FILE
        )
    ) forward_engine (
        .clk                             (clk),
        .reset_n                         (reset_n),
        .start                           (forward_start),

        .load_we                         (forward_load_we),
        .load_addr                       (forward_load_addr),
        .load_data                       (forward_load_data),

        .read_addr                       (forward_read_addr),
        .read_data                       (forward_read_data),

        .busy                            (forward_busy),
        .done                            (forward_done),

        .cycles                          (forward_cycles),

        .preprocess_multiplication_count (
            forward_preprocess_count
        ),

        .butterfly_count                 (
            forward_butterfly_count
        )
    );

    pointwise_mul256_core pointwise_engine (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (pointwise_start),

        .load_we              (pointwise_load_we),
        .load_bank            (pointwise_load_bank),
        .load_addr            (pointwise_load_addr),
        .load_data            (pointwise_load_data),

        .read_addr            (pointwise_read_addr),
        .read_data            (pointwise_read_data),

        .busy                 (pointwise_busy),
        .done                 (pointwise_done),

        .cycles               (pointwise_cycles),
        .multiplication_count (pointwise_count)
    );

    inverse_ntt256_core #(
        .INVERSE_TWIDDLE_INIT_FILE(
            INVERSE_TWIDDLE_INIT_FILE
        ),

        .INVERSE_SCALE_INIT_FILE(
            INVERSE_SCALE_INIT_FILE
        )
    ) inverse_engine (
        .clk                              (clk),
        .reset_n                          (reset_n),
        .start                            (inverse_start),

        .load_we                          (inverse_load_we),
        .load_addr                        (inverse_load_addr),
        .load_data                        (inverse_load_data),

        .read_addr                        (read_addr),
        .read_data                        (inverse_read_data),

        .busy                             (inverse_busy),
        .done                             (inverse_done),

        .cycles                           (inverse_cycles),

        .postprocess_multiplication_count (
            inverse_postprocess_count
        ),

        .butterfly_count                  (
            inverse_butterfly_count
        )
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            transfer_index <=
                8'd0;

            transfer_value <=
                32'd0;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            modular_multiplication_count <=
                13'd0;
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
                        transfer_index <=
                            8'd0;

                        cycles <=
                            32'd0;

                        modular_multiplication_count <=
                            13'd0;

                        busy <=
                            1'b1;

                        state <=
                            STATE_SOURCE_A_READ;
                    end
                end

                /*
                 * Copy natural-order polynomial A into the reusable
                 * forward NTT engine.
                 */
                STATE_SOURCE_A_READ:
                begin
                    state <=
                        STATE_SOURCE_A_CAPTURE;
                end

                STATE_SOURCE_A_CAPTURE:
                begin
                    transfer_value <=
                        source_a_read_data;

                    state <=
                        STATE_FORWARD_A_LOAD;
                end

                STATE_FORWARD_A_LOAD:
                begin
                    if (transfer_index == 8'd255)
                    begin
                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_FORWARD_A_START;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_SOURCE_A_READ;
                    end
                end

                STATE_FORWARD_A_START:
                begin
                    state <=
                        STATE_FORWARD_A_WAIT;
                end

                STATE_FORWARD_A_WAIT:
                begin
                    if (forward_done)
                    begin
                        modular_multiplication_count <=
                            modular_multiplication_count
                            + 13'd1280;

                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_FORWARD_A_READ;
                    end
                end

                /*
                 * Copy transform A into pointwise input bank A.
                 */
                STATE_FORWARD_A_READ:
                begin
                    state <=
                        STATE_FORWARD_A_CAPTURE;
                end

                STATE_FORWARD_A_CAPTURE:
                begin
                    transfer_value <=
                        forward_read_data;

                    state <=
                        STATE_POINTWISE_A_LOAD;
                end

                STATE_POINTWISE_A_LOAD:
                begin
                    if (transfer_index == 8'd255)
                    begin
                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_SOURCE_B_READ;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_FORWARD_A_READ;
                    end
                end

                /*
                 * Copy natural-order polynomial B into the reusable
                 * forward NTT engine.
                 */
                STATE_SOURCE_B_READ:
                begin
                    state <=
                        STATE_SOURCE_B_CAPTURE;
                end

                STATE_SOURCE_B_CAPTURE:
                begin
                    transfer_value <=
                        source_b_read_data;

                    state <=
                        STATE_FORWARD_B_LOAD;
                end

                STATE_FORWARD_B_LOAD:
                begin
                    if (transfer_index == 8'd255)
                    begin
                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_FORWARD_B_START;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_SOURCE_B_READ;
                    end
                end

                STATE_FORWARD_B_START:
                begin
                    state <=
                        STATE_FORWARD_B_WAIT;
                end

                STATE_FORWARD_B_WAIT:
                begin
                    if (forward_done)
                    begin
                        modular_multiplication_count <=
                            modular_multiplication_count
                            + 13'd1280;

                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_FORWARD_B_READ;
                    end
                end

                /*
                 * Copy transform B into pointwise input bank B.
                 */
                STATE_FORWARD_B_READ:
                begin
                    state <=
                        STATE_FORWARD_B_CAPTURE;
                end

                STATE_FORWARD_B_CAPTURE:
                begin
                    transfer_value <=
                        forward_read_data;

                    state <=
                        STATE_POINTWISE_B_LOAD;
                end

                STATE_POINTWISE_B_LOAD:
                begin
                    if (transfer_index == 8'd255)
                    begin
                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_POINTWISE_START;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_FORWARD_B_READ;
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
                        modular_multiplication_count <=
                            modular_multiplication_count
                            + 13'd256;

                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_POINTWISE_READ;
                    end
                end

                /*
                 * Copy pointwise products into the inverse NTT.
                 */
                STATE_POINTWISE_READ:
                begin
                    state <=
                        STATE_POINTWISE_CAPTURE;
                end

                STATE_POINTWISE_CAPTURE:
                begin
                    transfer_value <=
                        pointwise_read_data;

                    state <=
                        STATE_INVERSE_LOAD;
                end

                STATE_INVERSE_LOAD:
                begin
                    if (transfer_index == 8'd255)
                    begin
                        transfer_index <=
                            8'd0;

                        state <=
                            STATE_INVERSE_START;
                    end
                    else
                    begin
                        transfer_index <=
                            transfer_index + 1'b1;

                        state <=
                            STATE_POINTWISE_READ;
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
                        modular_multiplication_count <=
                            modular_multiplication_count
                            + 13'd1280;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;

                        state <=
                            STATE_IDLE;
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

endmodule
