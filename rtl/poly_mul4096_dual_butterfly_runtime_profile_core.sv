`timescale 1ns/1ps

/*
 * Runtime-profile N=4096 negacyclic polynomial multiplier with
 * two butterflies per polynomial and four scalar coefficients per
 * linear arithmetic group.
 *
 * Ring:
 *
 *     Z_q[X] / (X^4096 + 1)
 *
 * Runtime profile banks:
 *
 *     0: psi^j twist factors
 *     1: forward DIF twiddles
 *     2: inverse DIT twiddles
 *     3: N^-1 * psi^-j inverse-scale factors
 *
 * Coefficient memory:
 *
 *     A: four physical 1024 x 32 BRAM banks
 *     B: four physical 1024 x 32 BRAM banks
 *
 * Arithmetic phases:
 *
 *   1. Twist four A and four B coefficients concurrently.
 *   2. Run two forward DIF butterflies on A and two on B concurrently.
 *   3. Pointwise-multiply four matching spectra concurrently.
 *   4. Run two inverse DIT butterflies on A concurrently.
 *   5. Postscale four output coefficients concurrently.
 *
 * Exact target timing with the validated radix-4 modmul_core:
 *
 * Exact target timing with registered butterfly inputs:
 *
 *     preprocessing:  1024 * 22       =  22528 cycles
 *     forward DIF:    1 + 12288 * 23  = 282625 cycles
 *     pointwise:      1024 * 21       =  21504 cycles
 *     inverse DIT:    1 + 12288 * 23  = 282625 cycles
 *     postprocessing: 1024 * 22       =  22528 cycles
 *                                           ------
 *     total:                               631810 cycles
 *
 * The additional 24576 clocks isolate coefficient BRAM outputs from
 * the multiplier input registers in all forward and inverse paired
 * butterflies.
 */
module poly_mul4096_dual_butterfly_runtime_profile_core (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        start,

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

    input  logic        profile_modulus_we,
    input  logic [31:0] profile_modulus_data,

    input  logic        profile_we,
    input  logic [1:0]  profile_bank,
    input  logic [11:0] profile_addr,
    input  logic [31:0] profile_data,

    input  logic        profile_commit,

    output logic        profile_ready,
    output logic [31:0] active_modulus,

    output logic        busy,
    output logic        done,

    output logic [31:0] cycles,
    output logic [16:0] multiplication_count,

    output logic [13:0] preprocessing_count,
    output logic [15:0] forward_butterfly_count,
    output logic [12:0] pointwise_count,
    output logic [14:0] inverse_butterfly_count,
    output logic [12:0] postprocessing_count
);

    localparam logic [1:0] PROFILE_BANK_TWIST =
        2'd0;

    localparam logic [1:0] PROFILE_BANK_FORWARD_TWIDDLE =
        2'd1;

    localparam logic [1:0] PROFILE_BANK_INVERSE_TWIDDLE =
        2'd2;

    localparam logic [1:0] PROFILE_BANK_INVERSE_SCALE =
        2'd3;

    localparam logic [9:0] LAST_LINEAR_GROUP =
        10'd1023;

    localparam logic [13:0] LAST_PAIRED_ENTRY =
        14'd12287;

    /*
     * Seventeen bits count the 90112 modular multiplications of one
     * product with headroom to 131071. Widen this constant, the
     * counter, and the multiplication_count ports together if a
     * future schedule multiplies more per product.
     */
    localparam logic [16:0] TOTAL_MODULAR_MULTIPLICATIONS =
        17'd90112;

    typedef enum logic [4:0] {
        STATE_IDLE,

        STATE_PREP_READ01_ISSUE,
        STATE_PREP_CAPTURE01_ISSUE23,
        STATE_PREP_CAPTURE23_START,
        STATE_PREP_WAIT,
        STATE_PREP_WRITEBACK,

        STATE_FORWARD_SCHEDULE_START,
        STATE_FORWARD_READ_ISSUE,
        STATE_FORWARD_READ_CAPTURE,
        STATE_FORWARD_WAIT,
        STATE_FORWARD_WRITEBACK,

        STATE_POINTWISE_READ_ISSUE,
        STATE_POINTWISE_READ_CAPTURE_START,
        STATE_POINTWISE_WAIT,
        STATE_POINTWISE_WRITEBACK,

        STATE_INVERSE_SCHEDULE_START,
        STATE_INVERSE_READ_ISSUE,
        STATE_INVERSE_READ_CAPTURE,
        STATE_INVERSE_WAIT,
        STATE_INVERSE_WRITEBACK,

        STATE_POST_READ01_ISSUE,
        STATE_POST_CAPTURE01_ISSUE23,
        STATE_POST_CAPTURE23_START,
        STATE_POST_WAIT,
        STATE_POST_WRITEBACK
    } state_t;

    state_t state;

    logic [31:0] modulus_register;
    logic [9:0]  linear_group_index;
    logic [13:0] paired_entry_count;

    logic [11:0] linear_base_address;

    assign linear_base_address = {
        linear_group_index,
        2'b00
    };

    assign active_modulus =
        modulus_register;

    /*
     * Conflict-free idle inspection groups. The requested address is
     * always position zero. The other three low-bit rotations complete
     * the four-bank group.
     */
    logic [11:0] inspect_a_addr0;
    logic [11:0] inspect_a_addr1;
    logic [11:0] inspect_a_addr2;
    logic [11:0] inspect_a_addr3;

    logic [11:0] inspect_b_addr0;
    logic [11:0] inspect_b_addr1;
    logic [11:0] inspect_b_addr2;
    logic [11:0] inspect_b_addr3;

    assign inspect_a_addr0 =
        read_a_addr;

    assign inspect_a_addr1 = {
        read_a_addr[11:2],
        read_a_addr[1:0] + 2'd1
    };

    assign inspect_a_addr2 = {
        read_a_addr[11:2],
        read_a_addr[1:0] + 2'd2
    };

    assign inspect_a_addr3 = {
        read_a_addr[11:2],
        read_a_addr[1:0] + 2'd3
    };

    assign inspect_b_addr0 =
        read_b_addr;

    assign inspect_b_addr1 = {
        read_b_addr[11:2],
        read_b_addr[1:0] + 2'd1
    };

    assign inspect_b_addr2 = {
        read_b_addr[11:2],
        read_b_addr[1:0] + 2'd2
    };

    assign inspect_b_addr3 = {
        read_b_addr[11:2],
        read_b_addr[1:0] + 2'd3
    };

    /*
     * Shared paired-butterfly schedule.
     */
    logic schedule_start;
    logic schedule_descending;
    logic schedule_advance;

    logic schedule_busy;
    logic schedule_valid;
    logic schedule_done;

    logic [3:0] schedule_stage;
    logic [9:0] schedule_pair_index;

    logic [11:0] schedule_address0_a;
    logic [11:0] schedule_address0_b;
    logic [11:0] schedule_address1_a;
    logic [11:0] schedule_address1_b;

    logic [11:0] schedule_twiddle_address0;
    logic [11:0] schedule_twiddle_address1;

    assign schedule_start =
        state == STATE_FORWARD_SCHEDULE_START
        || state == STATE_INVERSE_SCHEDULE_START;

    assign schedule_descending =
        state == STATE_FORWARD_SCHEDULE_START;

    assign schedule_advance =
        state == STATE_FORWARD_WRITEBACK
        || state == STATE_INVERSE_WRITEBACK;

    ntt4096_paired_schedule_core schedule (
        .clk               (clk),
        .reset_n           (reset_n),

        .start             (schedule_start),
        .descending        (schedule_descending),
        .advance           (schedule_advance),

        .busy              (schedule_busy),
        .valid             (schedule_valid),
        .done              (schedule_done),

        .stage_bit         (schedule_stage),
        .pair_index        (schedule_pair_index),

        .address0_a        (schedule_address0_a),
        .address0_b        (schedule_address0_b),
        .address1_a        (schedule_address1_a),
        .address1_b        (schedule_address1_b),

        .twiddle_address0  (schedule_twiddle_address0),
        .twiddle_address1  (schedule_twiddle_address1)
    );

    /*
     * Four runtime profile memories. Each one is a single true
     * dual-port 4096 x 32 block-RAM table.
     */
    logic twist_write_enable;
    logic forward_write_enable;
    logic inverse_write_enable;
    logic scale_write_enable;

    logic twist_read_enable;
    logic [11:0] twist_read_address0;
    logic [11:0] twist_read_address1;
    logic [31:0] twist_read_data0;
    logic [31:0] twist_read_data1;

    logic forward_read_enable;
    logic [31:0] forward_read_data0;
    logic [31:0] forward_read_data1;

    logic inverse_read_enable;
    logic [31:0] inverse_read_data0;
    logic [31:0] inverse_read_data1;

    logic scale_read_enable;
    logic [11:0] scale_read_address0;
    logic [11:0] scale_read_address1;
    logic [31:0] scale_read_data0;
    logic [31:0] scale_read_data1;

    assign twist_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_TWIST;

    assign forward_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_FORWARD_TWIDDLE;

    assign inverse_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_INVERSE_TWIDDLE;

    assign scale_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_INVERSE_SCALE;

    assign twist_read_enable =
        state == STATE_PREP_READ01_ISSUE
        || state == STATE_PREP_CAPTURE01_ISSUE23;

    assign twist_read_address0 =
        state == STATE_PREP_CAPTURE01_ISSUE23
            ? linear_base_address + 12'd2
            : linear_base_address;

    assign twist_read_address1 =
        state == STATE_PREP_CAPTURE01_ISSUE23
            ? linear_base_address + 12'd3
            : linear_base_address + 12'd1;

    assign forward_read_enable =
        state == STATE_FORWARD_READ_ISSUE;

    assign inverse_read_enable =
        state == STATE_INVERSE_READ_ISSUE;

    assign scale_read_enable =
        state == STATE_POST_READ01_ISSUE
        || state == STATE_POST_CAPTURE01_ISSUE23;

    assign scale_read_address0 =
        state == STATE_POST_CAPTURE01_ISSUE23
            ? linear_base_address + 12'd2
            : linear_base_address;

    assign scale_read_address1 =
        state == STATE_POST_CAPTURE01_ISSUE23
            ? linear_base_address + 12'd3
            : linear_base_address + 12'd1;

    ntt4096_profile_bram_dual_read twist_memory (
        .clk            (clk),

        .write_enable   (twist_write_enable),
        .write_address  (profile_addr),
        .write_data     (profile_data),

        .read_enable_a  (twist_read_enable),
        .read_address_a (twist_read_address0),
        .read_data_a    (twist_read_data0),

        .read_enable_b  (twist_read_enable),
        .read_address_b (twist_read_address1),
        .read_data_b    (twist_read_data1)
    );

    ntt4096_profile_bram_dual_read forward_twiddle_memory (
        .clk            (clk),

        .write_enable   (forward_write_enable),
        .write_address  (profile_addr),
        .write_data     (profile_data),

        .read_enable_a  (forward_read_enable),
        .read_address_a (schedule_twiddle_address0),
        .read_data_a    (forward_read_data0),

        .read_enable_b  (forward_read_enable),
        .read_address_b (schedule_twiddle_address1),
        .read_data_b    (forward_read_data1)
    );

    ntt4096_profile_bram_dual_read inverse_twiddle_memory (
        .clk            (clk),

        .write_enable   (inverse_write_enable),
        .write_address  (profile_addr),
        .write_data     (profile_data),

        .read_enable_a  (inverse_read_enable),
        .read_address_a (schedule_twiddle_address0),
        .read_data_a    (inverse_read_data0),

        .read_enable_b  (inverse_read_enable),
        .read_address_b (schedule_twiddle_address1),
        .read_data_b    (inverse_read_data1)
    );

    ntt4096_profile_bram_dual_read inverse_scale_memory (
        .clk            (clk),

        .write_enable   (scale_write_enable),
        .write_address  (profile_addr),
        .write_data     (profile_data),

        .read_enable_a  (scale_read_enable),
        .read_address_a (scale_read_address0),
        .read_data_a    (scale_read_data0),

        .read_enable_b  (scale_read_enable),
        .read_address_b (scale_read_address1),
        .read_data_b    (scale_read_data1)
    );

    /*
     * Coefficient-store interfaces.
     */
    logic a_read_valid;
    logic [11:0] a_read_addr0;
    logic [11:0] a_read_addr1;
    logic [11:0] a_read_addr2;
    logic [11:0] a_read_addr3;

    logic a_read_data_valid;
    logic [31:0] a_read_data0;
    logic [31:0] a_read_data1;
    logic [31:0] a_read_data2;
    logic [31:0] a_read_data3;

    logic a_write_valid;
    logic [11:0] a_write_addr0;
    logic [11:0] a_write_addr1;
    logic [11:0] a_write_addr2;
    logic [11:0] a_write_addr3;
    logic [31:0] a_write_data0;
    logic [31:0] a_write_data1;
    logic [31:0] a_write_data2;
    logic [31:0] a_write_data3;

    logic b_read_valid;
    logic [11:0] b_read_addr0;
    logic [11:0] b_read_addr1;
    logic [11:0] b_read_addr2;
    logic [11:0] b_read_addr3;

    logic b_read_data_valid;
    logic [31:0] b_read_data0;
    logic [31:0] b_read_data1;
    logic [31:0] b_read_data2;
    logic [31:0] b_read_data3;

    logic b_write_valid;
    logic [11:0] b_write_addr0;
    logic [11:0] b_write_addr1;
    logic [11:0] b_write_addr2;
    logic [11:0] b_write_addr3;
    logic [31:0] b_write_data0;
    logic [31:0] b_write_data1;
    logic [31:0] b_write_data2;
    logic [31:0] b_write_data3;

    assign read_a_data =
        a_read_data0;

    assign read_b_data =
        b_read_data0;

    always_comb
    begin
        a_read_valid =
            1'b0;

        a_read_addr0 =
            12'd0;

        a_read_addr1 =
            12'd1;

        a_read_addr2 =
            12'd2;

        a_read_addr3 =
            12'd3;

        /*
         * The physical coefficient store has independent read and write
         * ports.  Keep the idle A read port active during an external
         * load so a captured result can be streamed while the same
         * logical address is refilled on the following clock.
         *
         * This changes only idle external-port arbitration.  The busy
         * arithmetic state machine and its 631810-cycle schedule are
         * unchanged.
         */
        if (!busy)
        begin
            a_read_valid =
                1'b1;

            a_read_addr0 =
                inspect_a_addr0;

            a_read_addr1 =
                inspect_a_addr1;

            a_read_addr2 =
                inspect_a_addr2;

            a_read_addr3 =
                inspect_a_addr3;
        end
        else
        begin
            case (state)
                STATE_PREP_READ01_ISSUE,
                STATE_POINTWISE_READ_ISSUE,
                STATE_POST_READ01_ISSUE:
                begin
                    a_read_valid =
                        1'b1;

                    a_read_addr0 =
                        linear_base_address;

                    a_read_addr1 =
                        linear_base_address + 12'd1;

                    a_read_addr2 =
                        linear_base_address + 12'd2;

                    a_read_addr3 =
                        linear_base_address + 12'd3;
                end

                STATE_FORWARD_READ_ISSUE,
                STATE_INVERSE_READ_ISSUE:
                begin
                    a_read_valid =
                        1'b1;

                    a_read_addr0 =
                        schedule_address0_a;

                    a_read_addr1 =
                        schedule_address0_b;

                    a_read_addr2 =
                        schedule_address1_a;

                    a_read_addr3 =
                        schedule_address1_b;
                end

                default:
                begin
                end
            endcase
        end
    end

    always_comb
    begin
        b_read_valid =
            1'b0;

        b_read_addr0 =
            12'd0;

        b_read_addr1 =
            12'd1;

        b_read_addr2 =
            12'd2;

        b_read_addr3 =
            12'd3;

        if (!busy && !load_b_we)
        begin
            b_read_valid =
                1'b1;

            b_read_addr0 =
                inspect_b_addr0;

            b_read_addr1 =
                inspect_b_addr1;

            b_read_addr2 =
                inspect_b_addr2;

            b_read_addr3 =
                inspect_b_addr3;
        end
        else
        begin
            case (state)
                STATE_PREP_READ01_ISSUE,
                STATE_POINTWISE_READ_ISSUE:
                begin
                    b_read_valid =
                        1'b1;

                    b_read_addr0 =
                        linear_base_address;

                    b_read_addr1 =
                        linear_base_address + 12'd1;

                    b_read_addr2 =
                        linear_base_address + 12'd2;

                    b_read_addr3 =
                        linear_base_address + 12'd3;
                end

                STATE_FORWARD_READ_ISSUE:
                begin
                    b_read_valid =
                        1'b1;

                    b_read_addr0 =
                        schedule_address0_a;

                    b_read_addr1 =
                        schedule_address0_b;

                    b_read_addr2 =
                        schedule_address1_a;

                    b_read_addr3 =
                        schedule_address1_b;
                end

                default:
                begin
                end
            endcase
        end
    end

    /*
     * Captured linear-phase values. The coefficient group is captured
     * while the second pair of factor-table reads is issued.
     */
    logic [31:0] captured_a0;
    logic [31:0] captured_a1;
    logic [31:0] captured_a2;
    logic [31:0] captured_a3;

    logic [31:0] captured_b0;
    logic [31:0] captured_b1;
    logic [31:0] captured_b2;
    logic [31:0] captured_b3;

    logic [31:0] captured_factor0;
    logic [31:0] captured_factor1;

    /*
     * Eight scalar multipliers. Preprocessing uses all eight. The
     * pointwise and postprocessing phases use lanes zero through three.
     */
    logic scalar_start0;
    logic scalar_start1;
    logic scalar_start2;
    logic scalar_start3;
    logic scalar_start4;
    logic scalar_start5;
    logic scalar_start6;
    logic scalar_start7;

    logic [31:0] scalar_a0;
    logic [31:0] scalar_a1;
    logic [31:0] scalar_a2;
    logic [31:0] scalar_a3;
    logic [31:0] scalar_a4;
    logic [31:0] scalar_a5;
    logic [31:0] scalar_a6;
    logic [31:0] scalar_a7;

    logic [31:0] scalar_b0;
    logic [31:0] scalar_b1;
    logic [31:0] scalar_b2;
    logic [31:0] scalar_b3;
    logic [31:0] scalar_b4;
    logic [31:0] scalar_b5;
    logic [31:0] scalar_b6;
    logic [31:0] scalar_b7;

    logic scalar_busy0;
    logic scalar_busy1;
    logic scalar_busy2;
    logic scalar_busy3;
    logic scalar_busy4;
    logic scalar_busy5;
    logic scalar_busy6;
    logic scalar_busy7;

    logic scalar_done0;
    logic scalar_done1;
    logic scalar_done2;
    logic scalar_done3;
    logic scalar_done4;
    logic scalar_done5;
    logic scalar_done6;
    logic scalar_done7;

    logic [31:0] scalar_result0;
    logic [31:0] scalar_result1;
    logic [31:0] scalar_result2;
    logic [31:0] scalar_result3;
    logic [31:0] scalar_result4;
    logic [31:0] scalar_result5;
    logic [31:0] scalar_result6;
    logic [31:0] scalar_result7;

    always_comb
    begin
        scalar_start0 =
            1'b0;

        scalar_start1 =
            1'b0;

        scalar_start2 =
            1'b0;

        scalar_start3 =
            1'b0;

        scalar_start4 =
            1'b0;

        scalar_start5 =
            1'b0;

        scalar_start6 =
            1'b0;

        scalar_start7 =
            1'b0;

        scalar_a0 =
            32'd0;

        scalar_a1 =
            32'd0;

        scalar_a2 =
            32'd0;

        scalar_a3 =
            32'd0;

        scalar_a4 =
            32'd0;

        scalar_a5 =
            32'd0;

        scalar_a6 =
            32'd0;

        scalar_a7 =
            32'd0;

        scalar_b0 =
            32'd0;

        scalar_b1 =
            32'd0;

        scalar_b2 =
            32'd0;

        scalar_b3 =
            32'd0;

        scalar_b4 =
            32'd0;

        scalar_b5 =
            32'd0;

        scalar_b6 =
            32'd0;

        scalar_b7 =
            32'd0;

        case (state)
            STATE_PREP_CAPTURE23_START:
            begin
                scalar_start0 =
                    1'b1;

                scalar_start1 =
                    1'b1;

                scalar_start2 =
                    1'b1;

                scalar_start3 =
                    1'b1;

                scalar_start4 =
                    1'b1;

                scalar_start5 =
                    1'b1;

                scalar_start6 =
                    1'b1;

                scalar_start7 =
                    1'b1;

                scalar_a0 =
                    captured_a0;

                scalar_a1 =
                    captured_a1;

                scalar_a2 =
                    captured_a2;

                scalar_a3 =
                    captured_a3;

                scalar_a4 =
                    captured_b0;

                scalar_a5 =
                    captured_b1;

                scalar_a6 =
                    captured_b2;

                scalar_a7 =
                    captured_b3;

                scalar_b0 =
                    captured_factor0;

                scalar_b1 =
                    captured_factor1;

                scalar_b2 =
                    twist_read_data0;

                scalar_b3 =
                    twist_read_data1;

                scalar_b4 =
                    captured_factor0;

                scalar_b5 =
                    captured_factor1;

                scalar_b6 =
                    twist_read_data0;

                scalar_b7 =
                    twist_read_data1;
            end

            STATE_POINTWISE_READ_CAPTURE_START:
            begin
                scalar_start0 =
                    1'b1;

                scalar_start1 =
                    1'b1;

                scalar_start2 =
                    1'b1;

                scalar_start3 =
                    1'b1;

                scalar_a0 =
                    a_read_data0;

                scalar_a1 =
                    a_read_data1;

                scalar_a2 =
                    a_read_data2;

                scalar_a3 =
                    a_read_data3;

                scalar_b0 =
                    b_read_data0;

                scalar_b1 =
                    b_read_data1;

                scalar_b2 =
                    b_read_data2;

                scalar_b3 =
                    b_read_data3;
            end

            STATE_POST_CAPTURE23_START:
            begin
                scalar_start0 =
                    1'b1;

                scalar_start1 =
                    1'b1;

                scalar_start2 =
                    1'b1;

                scalar_start3 =
                    1'b1;

                scalar_a0 =
                    captured_a0;

                scalar_a1 =
                    captured_a1;

                scalar_a2 =
                    captured_a2;

                scalar_a3 =
                    captured_a3;

                scalar_b0 =
                    captured_factor0;

                scalar_b1 =
                    captured_factor1;

                scalar_b2 =
                    scale_read_data0;

                scalar_b3 =
                    scale_read_data1;
            end

            default:
            begin
            end
        endcase
    end

    modmul_core scalar_lane0 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start0),
        .a       (scalar_a0),
        .b       (scalar_b0),
        .q       (modulus_register),
        .result  (scalar_result0),
        .busy    (scalar_busy0),
        .done    (scalar_done0)
    );

    modmul_core scalar_lane1 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start1),
        .a       (scalar_a1),
        .b       (scalar_b1),
        .q       (modulus_register),
        .result  (scalar_result1),
        .busy    (scalar_busy1),
        .done    (scalar_done1)
    );

    modmul_core scalar_lane2 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start2),
        .a       (scalar_a2),
        .b       (scalar_b2),
        .q       (modulus_register),
        .result  (scalar_result2),
        .busy    (scalar_busy2),
        .done    (scalar_done2)
    );

    modmul_core scalar_lane3 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start3),
        .a       (scalar_a3),
        .b       (scalar_b3),
        .q       (modulus_register),
        .result  (scalar_result3),
        .busy    (scalar_busy3),
        .done    (scalar_done3)
    );

    modmul_core scalar_lane4 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start4),
        .a       (scalar_a4),
        .b       (scalar_b4),
        .q       (modulus_register),
        .result  (scalar_result4),
        .busy    (scalar_busy4),
        .done    (scalar_done4)
    );

    modmul_core scalar_lane5 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start5),
        .a       (scalar_a5),
        .b       (scalar_b5),
        .q       (modulus_register),
        .result  (scalar_result5),
        .busy    (scalar_busy5),
        .done    (scalar_done5)
    );

    modmul_core scalar_lane6 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start6),
        .a       (scalar_a6),
        .b       (scalar_b6),
        .q       (modulus_register),
        .result  (scalar_result6),
        .busy    (scalar_busy6),
        .done    (scalar_done6)
    );

    modmul_core scalar_lane7 (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start7),
        .a       (scalar_a7),
        .b       (scalar_b7),
        .q       (modulus_register),
        .result  (scalar_result7),
        .busy    (scalar_busy7),
        .done    (scalar_done7)
    );

    logic prep_scalars_done;
    logic four_scalars_done;

    assign prep_scalars_done =
        scalar_done0
        && scalar_done1
        && scalar_done2
        && scalar_done3
        && scalar_done4
        && scalar_done5
        && scalar_done6
        && scalar_done7;

    assign four_scalars_done =
        scalar_done0
        && scalar_done1
        && scalar_done2
        && scalar_done3;

    /*
     * Four butterfly lanes. A uses lanes zero and one in both forward
     * and inverse phases. B uses lanes two and three during forward.
     */
    logic butterfly_a_start;
    logic butterfly_b_start;
    logic butterfly_inverse_mode;

    logic butterfly_a0_busy;
    logic butterfly_a0_done;
    logic [31:0] butterfly_a0_out_a;
    logic [31:0] butterfly_a0_out_b;

    logic butterfly_a1_busy;
    logic butterfly_a1_done;
    logic [31:0] butterfly_a1_out_a;
    logic [31:0] butterfly_a1_out_b;

    logic butterfly_b0_busy;
    logic butterfly_b0_done;
    logic [31:0] butterfly_b0_out_a;
    logic [31:0] butterfly_b0_out_b;

    logic butterfly_b1_busy;
    logic butterfly_b1_done;
    logic [31:0] butterfly_b1_out_a;
    logic [31:0] butterfly_b1_out_b;

    assign butterfly_a_start =
        state == STATE_FORWARD_READ_CAPTURE
        || state == STATE_INVERSE_READ_CAPTURE;

    assign butterfly_b_start =
        state == STATE_FORWARD_READ_CAPTURE;

    assign butterfly_inverse_mode =
        state == STATE_INVERSE_READ_CAPTURE;

    ntt4096_dual_mode_butterfly_core butterfly_a0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (butterfly_a_start),

        .inverse_mode (butterfly_inverse_mode),
        .a            (a_read_data0),
        .b            (a_read_data1),
        .omega        (
            butterfly_inverse_mode
                ? inverse_read_data0
                : forward_read_data0
        ),
        .q            (modulus_register),

        .out_a        (butterfly_a0_out_a),
        .out_b        (butterfly_a0_out_b),
        .busy         (butterfly_a0_busy),
        .done         (butterfly_a0_done)
    );

    ntt4096_dual_mode_butterfly_core butterfly_a1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (butterfly_a_start),

        .inverse_mode (butterfly_inverse_mode),
        .a            (a_read_data2),
        .b            (a_read_data3),
        .omega        (
            butterfly_inverse_mode
                ? inverse_read_data1
                : forward_read_data1
        ),
        .q            (modulus_register),

        .out_a        (butterfly_a1_out_a),
        .out_b        (butterfly_a1_out_b),
        .busy         (butterfly_a1_busy),
        .done         (butterfly_a1_done)
    );

    ntt4096_dual_mode_butterfly_core butterfly_b0 (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (butterfly_b_start),

        .inverse_mode (1'b0),
        .a            (b_read_data0),
        .b            (b_read_data1),
        .omega        (forward_read_data0),
        .q            (modulus_register),

        .out_a        (butterfly_b0_out_a),
        .out_b        (butterfly_b0_out_b),
        .busy         (butterfly_b0_busy),
        .done         (butterfly_b0_done)
    );

    ntt4096_dual_mode_butterfly_core butterfly_b1 (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (butterfly_b_start),

        .inverse_mode (1'b0),
        .a            (b_read_data2),
        .b            (b_read_data3),
        .omega        (forward_read_data1),
        .q            (modulus_register),

        .out_a        (butterfly_b1_out_a),
        .out_b        (butterfly_b1_out_b),
        .busy         (butterfly_b1_busy),
        .done         (butterfly_b1_done)
    );

    logic forward_butterflies_done;
    logic inverse_butterflies_done;

    assign forward_butterflies_done =
        butterfly_a0_done
        && butterfly_a1_done
        && butterfly_b0_done
        && butterfly_b1_done;

    assign inverse_butterflies_done =
        butterfly_a0_done
        && butterfly_a1_done;

    /*
     * Coefficient writeback routing.
     */
    always_comb
    begin
        a_write_valid =
            1'b0;

        a_write_addr0 =
            12'd0;

        a_write_addr1 =
            12'd1;

        a_write_addr2 =
            12'd2;

        a_write_addr3 =
            12'd3;

        a_write_data0 =
            32'd0;

        a_write_data1 =
            32'd0;

        a_write_data2 =
            32'd0;

        a_write_data3 =
            32'd0;

        case (state)
            STATE_PREP_WRITEBACK:
            begin
                a_write_valid =
                    1'b1;

                a_write_addr0 =
                    linear_base_address;

                a_write_addr1 =
                    linear_base_address + 12'd1;

                a_write_addr2 =
                    linear_base_address + 12'd2;

                a_write_addr3 =
                    linear_base_address + 12'd3;

                a_write_data0 =
                    scalar_result0;

                a_write_data1 =
                    scalar_result1;

                a_write_data2 =
                    scalar_result2;

                a_write_data3 =
                    scalar_result3;
            end

            STATE_FORWARD_WRITEBACK,
            STATE_INVERSE_WRITEBACK:
            begin
                a_write_valid =
                    1'b1;

                a_write_addr0 =
                    schedule_address0_a;

                a_write_addr1 =
                    schedule_address0_b;

                a_write_addr2 =
                    schedule_address1_a;

                a_write_addr3 =
                    schedule_address1_b;

                a_write_data0 =
                    butterfly_a0_out_a;

                a_write_data1 =
                    butterfly_a0_out_b;

                a_write_data2 =
                    butterfly_a1_out_a;

                a_write_data3 =
                    butterfly_a1_out_b;
            end

            STATE_POINTWISE_WRITEBACK,
            STATE_POST_WRITEBACK:
            begin
                a_write_valid =
                    1'b1;

                a_write_addr0 =
                    linear_base_address;

                a_write_addr1 =
                    linear_base_address + 12'd1;

                a_write_addr2 =
                    linear_base_address + 12'd2;

                a_write_addr3 =
                    linear_base_address + 12'd3;

                a_write_data0 =
                    scalar_result0;

                a_write_data1 =
                    scalar_result1;

                a_write_data2 =
                    scalar_result2;

                a_write_data3 =
                    scalar_result3;
            end

            default:
            begin
            end
        endcase
    end

    always_comb
    begin
        b_write_valid =
            1'b0;

        b_write_addr0 =
            12'd0;

        b_write_addr1 =
            12'd1;

        b_write_addr2 =
            12'd2;

        b_write_addr3 =
            12'd3;

        b_write_data0 =
            32'd0;

        b_write_data1 =
            32'd0;

        b_write_data2 =
            32'd0;

        b_write_data3 =
            32'd0;

        case (state)
            STATE_PREP_WRITEBACK:
            begin
                b_write_valid =
                    1'b1;

                b_write_addr0 =
                    linear_base_address;

                b_write_addr1 =
                    linear_base_address + 12'd1;

                b_write_addr2 =
                    linear_base_address + 12'd2;

                b_write_addr3 =
                    linear_base_address + 12'd3;

                b_write_data0 =
                    scalar_result4;

                b_write_data1 =
                    scalar_result5;

                b_write_data2 =
                    scalar_result6;

                b_write_data3 =
                    scalar_result7;
            end

            STATE_FORWARD_WRITEBACK:
            begin
                b_write_valid =
                    1'b1;

                b_write_addr0 =
                    schedule_address0_a;

                b_write_addr1 =
                    schedule_address0_b;

                b_write_addr2 =
                    schedule_address1_a;

                b_write_addr3 =
                    schedule_address1_b;

                b_write_data0 =
                    butterfly_b0_out_a;

                b_write_data1 =
                    butterfly_b0_out_b;

                b_write_data2 =
                    butterfly_b1_out_a;

                b_write_data3 =
                    butterfly_b1_out_b;
            end

            default:
            begin
            end
        endcase
    end

    ntt4096_four_bank_coeff_store coefficient_store_a (
        .clk             (clk),
        .reset_n         (reset_n),

        .load_we         (load_a_we && !busy),
        .load_addr       (load_a_addr),
        .load_data       (load_a_data),

        .read_valid      (a_read_valid),
        .read_addr0      (a_read_addr0),
        .read_addr1      (a_read_addr1),
        .read_addr2      (a_read_addr2),
        .read_addr3      (a_read_addr3),

        .read_data_valid (a_read_data_valid),
        .read_data0      (a_read_data0),
        .read_data1      (a_read_data1),
        .read_data2      (a_read_data2),
        .read_data3      (a_read_data3),

        .write_valid     (a_write_valid),
        .write_addr0     (a_write_addr0),
        .write_addr1     (a_write_addr1),
        .write_addr2     (a_write_addr2),
        .write_addr3     (a_write_addr3),
        .write_data0     (a_write_data0),
        .write_data1     (a_write_data1),
        .write_data2     (a_write_data2),
        .write_data3     (a_write_data3)
    );

    ntt4096_four_bank_coeff_store coefficient_store_b (
        .clk             (clk),
        .reset_n         (reset_n),

        .load_we         (load_b_we && !busy),
        .load_addr       (load_b_addr),
        .load_data       (load_b_data),

        .read_valid      (b_read_valid),
        .read_addr0      (b_read_addr0),
        .read_addr1      (b_read_addr1),
        .read_addr2      (b_read_addr2),
        .read_addr3      (b_read_addr3),

        .read_data_valid (b_read_data_valid),
        .read_data0      (b_read_data0),
        .read_data1      (b_read_data1),
        .read_data2      (b_read_data2),
        .read_data3      (b_read_data3),

        .write_valid     (b_write_valid),
        .write_addr0     (b_write_addr0),
        .write_addr1     (b_write_addr1),
        .write_addr2     (b_write_addr2),
        .write_addr3     (b_write_addr3),
        .write_data0     (b_write_data0),
        .write_data1     (b_write_data1),
        .write_data2     (b_write_data2),
        .write_data3     (b_write_data3)
    );

    /*
     * Controller and exact operation counts.
     */
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <=
                STATE_IDLE;

            modulus_register <=
                32'd0;

            profile_ready <=
                1'b0;

            busy <=
                1'b0;

            done <=
                1'b0;

            cycles <=
                32'd0;

            multiplication_count <=
                17'd0;

            preprocessing_count <=
                14'd0;

            forward_butterfly_count <=
                16'd0;

            pointwise_count <=
                13'd0;

            inverse_butterfly_count <=
                15'd0;

            postprocessing_count <=
                13'd0;

            linear_group_index <=
                10'd0;

            paired_entry_count <=
                14'd0;

            captured_a0 <=
                32'd0;

            captured_a1 <=
                32'd0;

            captured_a2 <=
                32'd0;

            captured_a3 <=
                32'd0;

            captured_b0 <=
                32'd0;

            captured_b1 <=
                32'd0;

            captured_b2 <=
                32'd0;

            captured_b3 <=
                32'd0;

            captured_factor0 <=
                32'd0;

            captured_factor1 <=
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

            if (!busy)
            begin
                if (profile_modulus_we)
                begin
                    modulus_register <=
                        profile_modulus_data;

                    profile_ready <=
                        1'b0;
                end

                if (profile_we)
                begin
                    profile_ready <=
                        1'b0;
                end

                if (profile_commit)
                begin
                    profile_ready <=
                        1'b1;
                end
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && profile_ready)
                    begin
                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        multiplication_count <=
                            17'd0;

                        preprocessing_count <=
                            14'd0;

                        forward_butterfly_count <=
                            16'd0;

                        pointwise_count <=
                            13'd0;

                        inverse_butterfly_count <=
                            15'd0;

                        postprocessing_count <=
                            13'd0;

                        linear_group_index <=
                            10'd0;

                        paired_entry_count <=
                            14'd0;

                        state <=
                            STATE_PREP_READ01_ISSUE;
                    end
                end

                STATE_PREP_READ01_ISSUE:
                begin
                    state <=
                        STATE_PREP_CAPTURE01_ISSUE23;
                end

                STATE_PREP_CAPTURE01_ISSUE23:
                begin
                    captured_a0 <=
                        a_read_data0;

                    captured_a1 <=
                        a_read_data1;

                    captured_a2 <=
                        a_read_data2;

                    captured_a3 <=
                        a_read_data3;

                    captured_b0 <=
                        b_read_data0;

                    captured_b1 <=
                        b_read_data1;

                    captured_b2 <=
                        b_read_data2;

                    captured_b3 <=
                        b_read_data3;

                    captured_factor0 <=
                        twist_read_data0;

                    captured_factor1 <=
                        twist_read_data1;

                    state <=
                        STATE_PREP_CAPTURE23_START;
                end

                STATE_PREP_CAPTURE23_START:
                begin
                    state <=
                        STATE_PREP_WAIT;
                end

                STATE_PREP_WAIT:
                begin
                    if (prep_scalars_done)
                    begin
                        state <=
                            STATE_PREP_WRITEBACK;
                    end
                end

                STATE_PREP_WRITEBACK:
                begin
                    multiplication_count <=
                        multiplication_count + 5'd8;

                    preprocessing_count <=
                        preprocessing_count + 5'd8;

                    if (linear_group_index == LAST_LINEAR_GROUP)
                    begin
                        linear_group_index <=
                            10'd0;

                        paired_entry_count <=
                            14'd0;

                        state <=
                            STATE_FORWARD_SCHEDULE_START;
                    end
                    else
                    begin
                        linear_group_index <=
                            linear_group_index + 1'b1;

                        state <=
                            STATE_PREP_READ01_ISSUE;
                    end
                end

                STATE_FORWARD_SCHEDULE_START:
                begin
                    state <=
                        STATE_FORWARD_READ_ISSUE;
                end

                STATE_FORWARD_READ_ISSUE:
                begin
                    state <=
                        STATE_FORWARD_READ_CAPTURE;
                end

                STATE_FORWARD_READ_CAPTURE:
                begin
                    state <=
                        STATE_FORWARD_WAIT;
                end

                STATE_FORWARD_WAIT:
                begin
                    if (forward_butterflies_done)
                    begin
                        state <=
                            STATE_FORWARD_WRITEBACK;
                    end
                end

                STATE_FORWARD_WRITEBACK:
                begin
                    multiplication_count <=
                        multiplication_count + 3'd4;

                    forward_butterfly_count <=
                        forward_butterfly_count + 3'd4;

                    if (paired_entry_count == LAST_PAIRED_ENTRY)
                    begin
                        linear_group_index <=
                            10'd0;

                        paired_entry_count <=
                            14'd0;

                        state <=
                            STATE_POINTWISE_READ_ISSUE;
                    end
                    else
                    begin
                        paired_entry_count <=
                            paired_entry_count + 1'b1;

                        state <=
                            STATE_FORWARD_READ_ISSUE;
                    end
                end

                STATE_POINTWISE_READ_ISSUE:
                begin
                    state <=
                        STATE_POINTWISE_READ_CAPTURE_START;
                end

                STATE_POINTWISE_READ_CAPTURE_START:
                begin
                    state <=
                        STATE_POINTWISE_WAIT;
                end

                STATE_POINTWISE_WAIT:
                begin
                    if (four_scalars_done)
                    begin
                        state <=
                            STATE_POINTWISE_WRITEBACK;
                    end
                end

                STATE_POINTWISE_WRITEBACK:
                begin
                    multiplication_count <=
                        multiplication_count + 3'd4;

                    pointwise_count <=
                        pointwise_count + 3'd4;

                    if (linear_group_index == LAST_LINEAR_GROUP)
                    begin
                        linear_group_index <=
                            10'd0;

                        paired_entry_count <=
                            14'd0;

                        state <=
                            STATE_INVERSE_SCHEDULE_START;
                    end
                    else
                    begin
                        linear_group_index <=
                            linear_group_index + 1'b1;

                        state <=
                            STATE_POINTWISE_READ_ISSUE;
                    end
                end

                STATE_INVERSE_SCHEDULE_START:
                begin
                    state <=
                        STATE_INVERSE_READ_ISSUE;
                end

                STATE_INVERSE_READ_ISSUE:
                begin
                    state <=
                        STATE_INVERSE_READ_CAPTURE;
                end

                STATE_INVERSE_READ_CAPTURE:
                begin
                    state <=
                        STATE_INVERSE_WAIT;
                end

                STATE_INVERSE_WAIT:
                begin
                    if (inverse_butterflies_done)
                    begin
                        state <=
                            STATE_INVERSE_WRITEBACK;
                    end
                end

                STATE_INVERSE_WRITEBACK:
                begin
                    multiplication_count <=
                        multiplication_count + 2'd2;

                    inverse_butterfly_count <=
                        inverse_butterfly_count + 2'd2;

                    if (paired_entry_count == LAST_PAIRED_ENTRY)
                    begin
                        linear_group_index <=
                            10'd0;

                        paired_entry_count <=
                            14'd0;

                        state <=
                            STATE_POST_READ01_ISSUE;
                    end
                    else
                    begin
                        paired_entry_count <=
                            paired_entry_count + 1'b1;

                        state <=
                            STATE_INVERSE_READ_ISSUE;
                    end
                end

                STATE_POST_READ01_ISSUE:
                begin
                    state <=
                        STATE_POST_CAPTURE01_ISSUE23;
                end

                STATE_POST_CAPTURE01_ISSUE23:
                begin
                    captured_a0 <=
                        a_read_data0;

                    captured_a1 <=
                        a_read_data1;

                    captured_a2 <=
                        a_read_data2;

                    captured_a3 <=
                        a_read_data3;

                    captured_factor0 <=
                        scale_read_data0;

                    captured_factor1 <=
                        scale_read_data1;

                    state <=
                        STATE_POST_CAPTURE23_START;
                end

                STATE_POST_CAPTURE23_START:
                begin
                    state <=
                        STATE_POST_WAIT;
                end

                STATE_POST_WAIT:
                begin
                    if (four_scalars_done)
                    begin
                        state <=
                            STATE_POST_WRITEBACK;
                    end
                end

                STATE_POST_WRITEBACK:
                begin
                    multiplication_count <=
                        multiplication_count + 3'd4;

                    postprocessing_count <=
                        postprocessing_count + 3'd4;

                    if (linear_group_index == LAST_LINEAR_GROUP)
                    begin
                        multiplication_count <=
                            TOTAL_MODULAR_MULTIPLICATIONS;

                        busy <=
                            1'b0;

                        done <=
                            1'b1;

                        state <=
                            STATE_IDLE;
                    end
                    else
                    begin
                        linear_group_index <=
                            linear_group_index + 1'b1;

                        state <=
                            STATE_POST_READ01_ISSUE;
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
        if (start && busy)
        begin
            $display(
                "ERROR: dual-butterfly polynomial start attempted while busy"
            );

            $fatal(1);
        end

        if (start && !profile_ready)
        begin
            $display(
                "ERROR: dual-butterfly polynomial started without profile"
            );

            $fatal(1);
        end

        if (
            (
                profile_we
                || profile_modulus_we
                || profile_commit
            )
            && busy
        )
        begin
            $display(
                "ERROR: runtime profile changed while core was busy"
            );

            $fatal(1);
        end

        if (
            (
                state == STATE_PREP_CAPTURE01_ISSUE23
                || state == STATE_POINTWISE_READ_CAPTURE_START
                || state == STATE_POST_CAPTURE01_ISSUE23
            )
            && !a_read_data_valid
        )
        begin
            $display(
                "ERROR: coefficient A read data was not valid"
            );

            $fatal(1);
        end

        if (
            (
                state == STATE_PREP_CAPTURE01_ISSUE23
                || state == STATE_POINTWISE_READ_CAPTURE_START
                || state == STATE_FORWARD_READ_CAPTURE
            )
            && !b_read_data_valid
        )
        begin
            $display(
                "ERROR: coefficient B read data was not valid"
            );

            $fatal(1);
        end

        if (
            state == STATE_FORWARD_READ_CAPTURE
            && (
                butterfly_a0_busy
                || butterfly_a1_busy
                || butterfly_b0_busy
                || butterfly_b1_busy
            )
        )
        begin
            $display(
                "ERROR: forward butterfly launch while lane was busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_INVERSE_READ_CAPTURE
            && (
                butterfly_a0_busy
                || butterfly_a1_busy
            )
        )
        begin
            $display(
                "ERROR: inverse butterfly launch while lane was busy"
            );

            $fatal(1);
        end

        if (
            done
            && (
                multiplication_count != TOTAL_MODULAR_MULTIPLICATIONS
                || preprocessing_count != 14'd8192
                || forward_butterfly_count != 16'd49152
                || pointwise_count != 13'd4096
                || inverse_butterfly_count != 15'd24576
                || postprocessing_count != 13'd4096
            )
        )
        begin
            $display(
                "ERROR: completed product reported wrong operation counts"
            );

            $fatal(1);
        end
    end

`endif

endmodule
