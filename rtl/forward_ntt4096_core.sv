`timescale 1ns/1ps

/*
 * Complete N=4096 forward negacyclic NTT.
 *
 * Input:
 *     natural-order coefficients a[j]
 *
 * Preprocessing:
 *     twisted = a[j] * psi^j mod q
 *     twisted is written to bit_reverse(j)
 *
 * Transform:
 *     radix-2 DIT cyclic NTT using omega
 *
 * Output:
 *     natural-order forward negacyclic NTT
 *
 * The external load interface is accepted only while idle. Result
 * reads are synchronous with one-clock latency after completion.
 */
module forward_ntt4096_core #(
    parameter TWIST_INIT_FILE =
        "../model/golden_n4096/twist_factors.mem",

    parameter TWIDDLE_INIT_FILE =
        "../model/golden_n4096/forward_twiddles.mem"
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
    output logic [12:0] preprocessing_count,
    output logic [14:0] butterfly_count
);

    localparam logic [31:0] MODULUS =
        ntt4096_profile_pkg::NTT_Q;

    localparam integer TOTAL_COEFFICIENTS =
        4096;

    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_PREP_READ_ISSUE,
        STATE_PREP_READ_CAPTURE,
        STATE_PREP_MUL_START,
        STATE_PREP_MUL_WAIT,
        STATE_PREP_WRITE,
        STATE_CYCLIC_START,
        STATE_CYCLIC_WAIT
    } state_t;

    state_t state;

    logic        input_port_a_enable;
    logic        input_port_a_write_enable;
    logic [11:0] input_port_a_address;
    logic [31:0] input_port_a_write_data;
    logic [31:0] input_port_a_read_data;

    logic [31:0] unused_input_port_b_read_data;

    logic twist_rom_enable;
    logic [31:0] twist_read_data;

    logic [11:0] coefficient_index;

    logic [31:0] captured_coefficient;
    logic [31:0] captured_twist;

    logic modmul_start;
    logic modmul_busy;
    logic modmul_done;
    logic [31:0] modmul_result;

    logic cyclic_start;
    logic cyclic_load_we;
    logic [11:0] cyclic_load_addr;
    logic [31:0] cyclic_load_data;

    logic cyclic_busy;
    logic cyclic_done;
    logic [31:0] cyclic_cycles;

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

    assign twist_rom_enable =
        state == STATE_PREP_READ_ISSUE;

    assign modmul_start =
        state == STATE_PREP_MUL_START;

    assign cyclic_start =
        state == STATE_CYCLIC_START;

    assign cyclic_load_we =
        state == STATE_PREP_WRITE;

    assign cyclic_load_addr =
        bit_reverse12(
            coefficient_index
        );

    assign cyclic_load_data =
        modmul_result;

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
                1'b1;

            input_port_a_write_enable =
                load_we;

            input_port_a_address =
                load_addr;

            input_port_a_write_data =
                load_data;
        end
        else if (state == STATE_PREP_READ_ISSUE)
        begin
            input_port_a_enable =
                1'b1;

            input_port_a_address =
                coefficient_index;
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

    ntt4096_factor_rom #(
        .INIT_FILE(
            TWIST_INIT_FILE
        )
    ) twist_rom (
        .clk       (clk),
        .enable    (twist_rom_enable),
        .address   (coefficient_index),
        .read_data (twist_read_data)
    );

    modmul_core preprocessing_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (modmul_start),

        .a       (captured_coefficient),
        .b       (captured_twist),
        .q       (MODULUS),

        .result  (modmul_result),
        .busy    (modmul_busy),
        .done    (modmul_done)
    );

    ntt4096_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            TWIDDLE_INIT_FILE
        )
    ) cyclic_transform (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (cyclic_start),

        .load_we         (cyclic_load_we),
        .load_addr       (cyclic_load_addr),
        .load_data       (cyclic_load_data),

        .read_addr       (read_addr),
        .read_data       (read_data),

        .busy            (cyclic_busy),
        .done            (cyclic_done),

        .cycles          (cyclic_cycles),
        .butterfly_count (butterfly_count)
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

            preprocessing_count <=
                13'd0;

            captured_coefficient <=
                32'd0;

            captured_twist <=
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
                            STATE_PREP_READ_ISSUE;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        coefficient_index <=
                            12'd0;

                        preprocessing_count <=
                            13'd0;
                    end
                end

                STATE_PREP_READ_ISSUE:
                begin
                    state <=
                        STATE_PREP_READ_CAPTURE;
                end

                STATE_PREP_READ_CAPTURE:
                begin
                    captured_coefficient <=
                        input_port_a_read_data;

                    captured_twist <=
                        twist_read_data;

                    state <=
                        STATE_PREP_MUL_START;
                end

                STATE_PREP_MUL_START:
                begin
                    state <=
                        STATE_PREP_MUL_WAIT;
                end

                STATE_PREP_MUL_WAIT:
                begin
                    if (modmul_done)
                    begin
                        state <=
                            STATE_PREP_WRITE;
                    end
                end

                STATE_PREP_WRITE:
                begin
                    preprocessing_count <=
                        preprocessing_count + 1'b1;

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
                            STATE_PREP_READ_ISSUE;
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
                        state <=
                            STATE_IDLE;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;
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
            state == STATE_PREP_MUL_START
            && modmul_busy
        )
        begin
            $display(
                "ERROR: N=4096 preprocessing multiplier start while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_CYCLIC_START
            && cyclic_busy
        )
        begin
            $display(
                "ERROR: N=4096 cyclic transform start while busy"
            );

            $fatal(1);
        end
    end

`endif

endmodule
