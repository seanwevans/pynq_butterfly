`timescale 1ns/1ps

/*
 * Shared-A/B NTT phase checkpoint for one RNS tower.
 *
 * One four-lane pipeline engine is time-multiplexed across:
 *
 *     1. forward DIF on coefficient store A
 *     2. forward DIF on coefficient store B
 *     3. inverse DIT on coefficient store A
 *
 * This is the resource-feasible integration geometry for XC7Z020:
 *
 *     one engine/tower  =  64 DSP48E1
 *     two RNS towers    = 128 DSP48E1
 *
 * Duplicating an engine for A and B would require 256 DSP48E1 across
 * two towers and cannot fit the 220-DSP device.
 *
 * Expected sequence timing:
 *
 *     3 * 6276 transform clocks
 *     + 3 controller-observation clocks
 *     ---------------------------------
 *     18831 clocks
 */
module ntt4096_four_butterfly_shared_ab_core (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        modulus_we,
    input  logic [31:0] modulus_data,
    input  logic [30:0] modulus_mu_data,

    input  logic        forward_twiddle_we,
    input  logic [11:0] forward_twiddle_addr,
    input  logic [31:0] forward_twiddle_data,

    input  logic        inverse_twiddle_we,
    input  logic [11:0] inverse_twiddle_addr,
    input  logic [31:0] inverse_twiddle_data,

    input  logic        load_a_we,
    input  logic [11:0] load_a_addr,
    input  logic [31:0] load_a_data,

    input  logic        load_b_we,
    input  logic [11:0] load_b_addr,
    input  logic [31:0] load_b_data,

    input  logic [11:0] read_a_addr,
    output logic [31:0] read_a_data,

    input  logic [11:0] read_b_addr,
    output logic [31:0] read_b_data,

    input  logic        start,

    output logic        busy,
    output logic        done,
    output logic [31:0] cycles,

    output logic [1:0]  transform_count,
    output logic [15:0] forward_butterfly_count,
    output logic [14:0] inverse_butterfly_count
);

    typedef enum logic [1:0] {
        PHASE_IDLE,
        PHASE_FORWARD_A,
        PHASE_FORWARD_B,
        PHASE_INVERSE_A
    } phase_state_t;

    phase_state_t phase_state;

    logic [31:0] modulus_register;
    logic [30:0] modulus_mu_register;

    logic        engine_start;
    logic        engine_busy;
    logic        engine_done;
    logic [31:0] engine_cycles;
    logic [14:0] engine_butterfly_count;

    assign engine_start =
        (
            phase_state == PHASE_IDLE
            && start
        )
        || (
            phase_state == PHASE_FORWARD_A
            && engine_done
        )
        || (
            phase_state == PHASE_FORWARD_B
            && engine_done
        );

    /*
     * On an engine-done observation edge, the next transform starts
     * immediately. These event terms select the next store and mode on
     * that same edge.
     */
    wire engine_target_b =
        phase_state == PHASE_FORWARD_B
        || (
            phase_state == PHASE_FORWARD_A
            && engine_done
        );

    wire engine_inverse_mode =
        phase_state == PHASE_INVERSE_A
        || (
            phase_state == PHASE_FORWARD_B
            && engine_done
        );

    logic             engine_coefficient_read_valid;
    logic [7:0][11:0] engine_coefficient_read_address;
    logic             engine_coefficient_read_data_valid;
    logic [7:0][31:0] engine_coefficient_read_data;

    logic             engine_twiddle_read_valid;
    logic [3:0][11:0] engine_twiddle_read_address;
    logic [3:0][31:0] engine_twiddle_read_data;

    logic             engine_coefficient_write_valid;
    logic [7:0][11:0] engine_coefficient_write_address;
    logic [7:0][31:0] engine_coefficient_write_data;

    ntt4096_four_butterfly_pipeline_engine_core engine (
        .clk                         (clk),
        .reset_n                     (reset_n),

        .start                       (engine_start),
        .inverse_mode                (engine_inverse_mode),

        .modulus                     (modulus_register),
        .modulus_mu                  (modulus_mu_register),

        .coefficient_read_valid      (
            engine_coefficient_read_valid
        ),

        .coefficient_read_address    (
            engine_coefficient_read_address
        ),

        .coefficient_read_data_valid (
            engine_coefficient_read_data_valid
        ),

        .coefficient_read_data       (
            engine_coefficient_read_data
        ),

        .twiddle_read_valid          (
            engine_twiddle_read_valid
        ),

        .twiddle_read_address        (
            engine_twiddle_read_address
        ),

        .twiddle_read_data           (
            engine_twiddle_read_data
        ),

        .coefficient_write_valid     (
            engine_coefficient_write_valid
        ),

        .coefficient_write_address   (
            engine_coefficient_write_address
        ),

        .coefficient_write_data      (
            engine_coefficient_write_data
        ),

        .busy                        (engine_busy),
        .done                        (engine_done),
        .cycles                      (engine_cycles),
        .butterfly_count             (engine_butterfly_count)
    );

    /*
     * Forward and inverse tables each provide four synchronous reads by
     * storing two identical dual-port BRAM copies.
     */
    logic [3:0][31:0] forward_twiddle_read_data;
    logic [3:0][31:0] inverse_twiddle_read_data;

    wire forward_twiddle_read_enable =
        engine_twiddle_read_valid
        && !engine_inverse_mode;

    wire inverse_twiddle_read_enable =
        engine_twiddle_read_valid
        && engine_inverse_mode;

    ntt4096_profile_bram_four_read forward_twiddle_memory (
        .clk           (clk),

        .write_enable  (
            forward_twiddle_we
            && !busy
        ),

        .write_address (forward_twiddle_addr),
        .write_data    (forward_twiddle_data),

        .read_enable   (forward_twiddle_read_enable),
        .read_address  (engine_twiddle_read_address),
        .read_data     (forward_twiddle_read_data)
    );

    ntt4096_profile_bram_four_read inverse_twiddle_memory (
        .clk           (clk),

        .write_enable  (
            inverse_twiddle_we
            && !busy
        ),

        .write_address (inverse_twiddle_addr),
        .write_data    (inverse_twiddle_data),

        .read_enable   (inverse_twiddle_read_enable),
        .read_address  (engine_twiddle_read_address),
        .read_data     (inverse_twiddle_read_data)
    );

    assign engine_twiddle_read_data =
        engine_inverse_mode
            ? inverse_twiddle_read_data
            : forward_twiddle_read_data;

    /*
     * Two independent eight-bank coefficient stores. The NTT engine
     * selects exactly one store at a time.
     */
    logic             a_store_read_valid;
    logic [7:0][11:0] a_store_read_address;
    logic             a_store_read_data_valid;
    logic [7:0][31:0] a_store_read_data;

    logic             a_store_write_valid;
    logic [7:0][11:0] a_store_write_address;
    logic [7:0][31:0] a_store_write_data;

    logic             b_store_read_valid;
    logic [7:0][11:0] b_store_read_address;
    logic             b_store_read_data_valid;
    logic [7:0][31:0] b_store_read_data;

    logic             b_store_write_valid;
    logic [7:0][11:0] b_store_write_address;
    logic [7:0][31:0] b_store_write_data;

    logic [7:0][11:0] inspect_a_address;
    logic [7:0][11:0] inspect_b_address;

    integer inspect_lane;

    always_comb
    begin
        for (
            inspect_lane = 0;
            inspect_lane < 8;
            inspect_lane = inspect_lane + 1
        )
        begin
            inspect_a_address[inspect_lane] =
                read_a_addr ^ inspect_lane[11:0];

            inspect_b_address[inspect_lane] =
                read_b_addr ^ inspect_lane[11:0];
        end

        if (busy)
        begin
            a_store_read_valid =
                engine_coefficient_read_valid
                && !engine_target_b;

            a_store_read_address =
                engine_coefficient_read_address;

            a_store_write_valid =
                engine_coefficient_write_valid
                && !engine_target_b;

            a_store_write_address =
                engine_coefficient_write_address;

            a_store_write_data =
                engine_coefficient_write_data;

            b_store_read_valid =
                engine_coefficient_read_valid
                && engine_target_b;

            b_store_read_address =
                engine_coefficient_read_address;

            b_store_write_valid =
                engine_coefficient_write_valid
                && engine_target_b;

            b_store_write_address =
                engine_coefficient_write_address;

            b_store_write_data =
                engine_coefficient_write_data;
        end
        else
        begin
            a_store_read_valid =
                1'b1;

            a_store_read_address =
                inspect_a_address;

            a_store_write_valid =
                1'b0;

            a_store_write_address =
                '0;

            a_store_write_data =
                '0;

            b_store_read_valid =
                1'b1;

            b_store_read_address =
                inspect_b_address;

            b_store_write_valid =
                1'b0;

            b_store_write_address =
                '0;

            b_store_write_data =
                '0;
        end
    end

    assign engine_coefficient_read_data_valid =
        engine_target_b
            ? b_store_read_data_valid
            : a_store_read_data_valid;

    assign engine_coefficient_read_data =
        engine_target_b
            ? b_store_read_data
            : a_store_read_data;

    assign read_a_data =
        a_store_read_data[0];

    assign read_b_data =
        b_store_read_data[0];

    ntt4096_eight_bank_coeff_store_runtime coefficient_store_a (
        .clk             (clk),

        .load_we         (
            load_a_we
            && !busy
        ),

        .load_addr       (load_a_addr),
        .load_data       (load_a_data),

        .read_valid      (a_store_read_valid),
        .read_addr       (a_store_read_address),
        .read_data_valid (a_store_read_data_valid),
        .read_data       (a_store_read_data),

        .write_valid     (a_store_write_valid),
        .write_addr      (a_store_write_address),
        .write_data      (a_store_write_data)
    );

    ntt4096_eight_bank_coeff_store_runtime coefficient_store_b (
        .clk             (clk),

        .load_we         (
            load_b_we
            && !busy
        ),

        .load_addr       (load_b_addr),
        .load_data       (load_b_data),

        .read_valid      (b_store_read_valid),
        .read_addr       (b_store_read_address),
        .read_data_valid (b_store_read_data_valid),
        .read_data       (b_store_read_data),

        .write_valid     (b_store_write_valid),
        .write_addr      (b_store_write_address),
        .write_data      (b_store_write_data)
    );

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            phase_state <=
                PHASE_IDLE;

            modulus_register <=
                32'd0;

            modulus_mu_register <=
                31'd0;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            transform_count <=
                2'd0;

            forward_butterfly_count <=
                16'd0;

            inverse_butterfly_count <=
                15'd0;
        end
        else
        begin
            done <=
                1'b0;

            if (!busy && modulus_we)
            begin
                modulus_register <=
                    modulus_data;

                modulus_mu_register <=
                    modulus_mu_data;
            end

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            case (phase_state)
                PHASE_IDLE:
                begin
                    if (start)
                    begin
                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        transform_count <=
                            2'd0;

                        forward_butterfly_count <=
                            16'd0;

                        inverse_butterfly_count <=
                            15'd0;

                        phase_state <=
                            PHASE_FORWARD_A;
                    end
                end

                PHASE_FORWARD_A:
                begin
                    if (engine_done)
                    begin
                        transform_count <=
                            transform_count + 1'b1;

                        forward_butterfly_count <=
                            forward_butterfly_count
                            + engine_butterfly_count;

                        phase_state <=
                            PHASE_FORWARD_B;
                    end
                end

                PHASE_FORWARD_B:
                begin
                    if (engine_done)
                    begin
                        transform_count <=
                            transform_count + 1'b1;

                        forward_butterfly_count <=
                            forward_butterfly_count
                            + engine_butterfly_count;

                        phase_state <=
                            PHASE_INVERSE_A;
                    end
                end

                PHASE_INVERSE_A:
                begin
                    if (engine_done)
                    begin
                        transform_count <=
                            2'd3;

                        inverse_butterfly_count <=
                            engine_butterfly_count;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;

                        phase_state <=
                            PHASE_IDLE;
                    end
                end

                default:
                begin
                    busy <=
                        1'b0;

                    phase_state <=
                        PHASE_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (busy && modulus_we)
        begin
            $display(
                "ERROR: modulus update attempted during shared-A/B sequence"
            );

            $fatal(1);
        end

        if (
            busy
            && (
                forward_twiddle_we
                || inverse_twiddle_we
                || load_a_we
                || load_b_we
            )
        )
        begin
            $display(
                "ERROR: memory update attempted during shared-A/B sequence"
            );

            $fatal(1);
        end
    end

`endif

endmodule
