`timescale 1ns/1ps

/*
 * Complete N=4096 inverse negacyclic NTT.
 *
 * Input:
 *     natural-order pointwise product
 *
 * Preparation:
 *     copy coefficient j to bit_reverse(j)
 *
 * Transform:
 *     radix-2 DIT cyclic inverse NTT using omega^-1
 *
 * Postprocessing:
 *     output[j] = cyclic[j] * N^-1 * psi^-j mod q
 *
 * Output:
 *     natural-order coefficients in Z_q[X] / (X^4096 + 1)
 *
 * The external load interface is accepted only while idle. Result
 * reads are synchronous with one-clock latency after completion.
 *
 * This checkpoint uses separate input, cyclic, and result memories.
 * A later full-product controller can reuse memories across phases.
 */
module inverse_ntt4096_core #(
    parameter INVERSE_SCALE_INIT_FILE =
        "../model/golden_n4096/inverse_scale_factors.mem",

    parameter INVERSE_TWIDDLE_INIT_FILE =
        "../model/golden_n4096/inverse_twiddles.mem"
) (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

    input  logic        load_we,
    input  logic [11:0] load_addr,
    input  logic [31:0] load_data,

    input  logic [11:0] read_addr,
    output logic [31:0] read_data,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [12:0] preparation_count,
    output logic [14:0] butterfly_count,
    output logic [12:0] postprocessing_count
);

    localparam logic [31:0] MODULUS =
        ntt4096_profile_pkg::NTT_Q;

    localparam integer TOTAL_COEFFICIENTS =
        4096;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_COPY_READ_ISSUE,
        STATE_COPY_READ_CAPTURE,
        STATE_COPY_WRITE,
        STATE_CYCLIC_START,
        STATE_CYCLIC_WAIT,
        STATE_POST_READ_ISSUE,
        STATE_POST_READ_CAPTURE,
        STATE_POST_MUL_START,
        STATE_POST_MUL_WAIT,
        STATE_POST_WRITE
    } state_t;

    state_t state;

    logic        input_port_a_enable;
    logic        input_port_a_write_enable;
    logic [11:0] input_port_a_address;
    logic [31:0] input_port_a_write_data;
    logic [31:0] input_port_a_read_data;

    logic [31:0] unused_input_port_b_read_data;

    logic        output_port_a_enable;
    logic        output_port_a_write_enable;
    logic [11:0] output_port_a_address;
    logic [31:0] output_port_a_write_data;
    logic [31:0] output_port_a_read_data;

    logic [31:0] unused_output_port_b_read_data;

    logic [11:0] coefficient_index;
    logic [31:0] captured_input;

    logic cyclic_start;
    logic cyclic_load_we;
    logic [11:0] cyclic_load_addr;
    logic [31:0] cyclic_load_data;

    logic [11:0] cyclic_read_addr;
    logic [31:0] cyclic_read_data;

    logic cyclic_busy;
    logic cyclic_done;
    logic [31:0] cyclic_cycles;

    logic scale_rom_enable;
    logic [31:0] inverse_scale_read_data;

    logic [31:0] captured_cyclic;
    logic [31:0] captured_inverse_scale;

    logic post_modmul_start;
    logic post_modmul_busy;
    logic post_modmul_done;
    logic [31:0] post_modmul_result;

    function automatic logic [11:0] bit_reverse12(
        input logic [11:0] value
    );
        begin
            bit_reverse12 =
            {
                value[0],
                value[1],
                value[2],
                value[3],
                value[4],
                value[5],
                value[6],
                value[7],
                value[8],
                value[9],
                value[10],
                value[11]
            };
        end
    endfunction

    assign cyclic_start =
        state == STATE_CYCLIC_START;

    assign cyclic_load_we =
        state == STATE_COPY_WRITE;

    assign cyclic_load_addr =
        bit_reverse12(
            coefficient_index
        );

    assign cyclic_load_data =
        captured_input;

    assign cyclic_read_addr =
        coefficient_index;

    assign scale_rom_enable =
        state == STATE_POST_READ_ISSUE;

    assign post_modmul_start =
        state == STATE_POST_MUL_START;

    assign read_data =
        output_port_a_read_data;

    always_comb
    begin
        input_port_a_enable =
            1'b0;

        input_port_a_write_enable =
            1'b0;

        input_port_a_address =
            12'd0;

        input_port_a_write_data =
            32'd0;

        if (!busy)
        begin
            input_port_a_enable =
                load_we;

            input_port_a_write_enable =
                load_we;

            input_port_a_address =
                load_addr;

            input_port_a_write_data =
                load_data;
        end
        else if (state == STATE_COPY_READ_ISSUE)
        begin
            input_port_a_enable =
                1'b1;

            input_port_a_address =
                coefficient_index;
        end
    end

    always_comb
    begin
        output_port_a_enable =
            1'b0;

        output_port_a_write_enable =
            1'b0;

        output_port_a_address =
            12'd0;

        output_port_a_write_data =
            32'd0;

        if (!busy)
        begin
            output_port_a_enable =
                1'b1;

            output_port_a_address =
                read_addr;
        end
        else if (state == STATE_POST_WRITE)
        begin
            output_port_a_enable =
                1'b1;

            output_port_a_write_enable =
                1'b1;

            output_port_a_address =
                coefficient_index;

            output_port_a_write_data =
                post_modmul_result;
        end
    end

    ntt4096_coeff_bram input_memory (
        .clk                 (clk),

        .port_a_enable       (input_port_a_enable),
        .port_a_write_enable (input_port_a_write_enable),
        .port_a_address      (input_port_a_address),
        .port_a_write_data   (input_port_a_write_data),
        .port_a_read_data    (input_port_a_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (12'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (unused_input_port_b_read_data)
    );

    ntt4096_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            INVERSE_TWIDDLE_INIT_FILE
        )
    ) cyclic_transform (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (cyclic_start),

        .load_we         (cyclic_load_we),
        .load_addr       (cyclic_load_addr),
        .load_data       (cyclic_load_data),

        .read_addr       (cyclic_read_addr),
        .read_data       (cyclic_read_data),

        .busy            (cyclic_busy),
        .done            (cyclic_done),

        .cycles          (cyclic_cycles),
        .butterfly_count (butterfly_count)
    );

    ntt4096_factor_rom #(
        .INIT_FILE(
            INVERSE_SCALE_INIT_FILE
        )
    ) inverse_scale_rom (
        .clk       (clk),
        .enable    (scale_rom_enable),
        .address   (coefficient_index),
        .read_data (inverse_scale_read_data)
    );

    modmul_core postprocessing_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (post_modmul_start),

        .a       (captured_cyclic),
        .b       (captured_inverse_scale),
        .q       (MODULUS),

        .result  (post_modmul_result),
        .busy    (post_modmul_busy),
        .done    (post_modmul_done)
    );

    ntt4096_coeff_bram output_memory (
        .clk                 (clk),

        .port_a_enable       (output_port_a_enable),
        .port_a_write_enable (output_port_a_write_enable),
        .port_a_address      (output_port_a_address),
        .port_a_write_data   (output_port_a_write_data),
        .port_a_read_data    (output_port_a_read_data),

        .port_b_enable       (1'b0),
        .port_b_write_enable (1'b0),
        .port_b_address      (12'd0),
        .port_b_write_data   (32'd0),
        .port_b_read_data    (unused_output_port_b_read_data)
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

            coefficient_index <=
                12'd0;

            preparation_count <=
                13'd0;

            postprocessing_count <=
                13'd0;

            captured_input <=
                32'd0;

            captured_cyclic <=
                32'd0;

            captured_inverse_scale <=
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
                            STATE_COPY_READ_ISSUE;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        coefficient_index <=
                            12'd0;

                        preparation_count <=
                            13'd0;

                        postprocessing_count <=
                            13'd0;
                    end
                end

                STATE_COPY_READ_ISSUE:
                begin
                    state <=
                        STATE_COPY_READ_CAPTURE;
                end

                STATE_COPY_READ_CAPTURE:
                begin
                    captured_input <=
                        input_port_a_read_data;

                    state <=
                        STATE_COPY_WRITE;
                end

                STATE_COPY_WRITE:
                begin
                    preparation_count <=
                        preparation_count + 1'b1;

                    if (
                        coefficient_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_CYCLIC_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;

                        state <=
                            STATE_COPY_READ_ISSUE;
                    end
                end

                STATE_CYCLIC_START:
                begin
                    state <=
                        STATE_CYCLIC_WAIT;
                end

                STATE_CYCLIC_WAIT:
                begin
                    if (cyclic_done)
                    begin
                        coefficient_index <=
                            12'd0;

                        state <=
                            STATE_POST_READ_ISSUE;
                    end
                end

                STATE_POST_READ_ISSUE:
                begin
                    state <=
                        STATE_POST_READ_CAPTURE;
                end

                STATE_POST_READ_CAPTURE:
                begin
                    captured_cyclic <=
                        cyclic_read_data;

                    captured_inverse_scale <=
                        inverse_scale_read_data;

                    state <=
                        STATE_POST_MUL_START;
                end

                STATE_POST_MUL_START:
                begin
                    state <=
                        STATE_POST_MUL_WAIT;
                end

                STATE_POST_MUL_WAIT:
                begin
                    if (post_modmul_done)
                    begin
                        state <=
                            STATE_POST_WRITE;
                    end
                end

                STATE_POST_WRITE:
                begin
                    postprocessing_count <=
                        postprocessing_count + 1'b1;

                    if (
                        coefficient_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_IDLE;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;

                        state <=
                            STATE_POST_READ_ISSUE;
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
            state == STATE_CYCLIC_START
            && cyclic_busy
        )
        begin
            $display(
                "ERROR: N=4096 inverse cyclic transform start while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_POST_MUL_START
            && post_modmul_busy
        )
        begin
            $display(
                "ERROR: N=4096 inverse postprocessing multiplier start while busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
