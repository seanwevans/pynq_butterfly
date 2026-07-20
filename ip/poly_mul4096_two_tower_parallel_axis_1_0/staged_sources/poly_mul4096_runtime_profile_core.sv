`timescale 1ns/1ps

/*
 * Runtime-profile two-bank N=4096 negacyclic polynomial multiplier.
 *
 * Ring:
 *
 *     Z_q[X] / (X^4096 + 1)
 *
 *     q is loaded at runtime.
 *
 * Memory architecture:
 *
 *     coefficient bank A : 4096 x 32-bit true dual-port BRAM
 *     coefficient bank B : 4096 x 32-bit true dual-port BRAM
 *
 * No phase owns a private coefficient copy. Every arithmetic phase
 * operates directly on these two banks:
 *
 *   1. Multiply A[j] and B[j] by psi^j in place.
 *   2. Run two lockstep forward DIF transforms in place.
 *      The spectra remain in bit-reversed physical order.
 *   3. Pointwise-multiply matching physical addresses and overwrite A.
 *   4. Run one inverse DIT transform in place on A.
 *      Bit-reversed input becomes natural-order output.
 *   5. Multiply A[j] by N^-1 * psi^-j in place.
 *
 * Runtime profile-memory architecture:
 *
 *     one writable twist-factor BRAM
 *     one writable forward-twiddle BRAM
 *     one writable inverse-twiddle BRAM
 *     one writable inverse-scale BRAM
 *
 * Arithmetic architecture:
 *
 *     two preprocessing modular multipliers
 *     two forward-DIF butterfly lanes
 *     one shared pointwise/postprocessing modular multiplier
 *     one inverse-DIT butterfly lane
 *
 * This checkpoint prioritizes coefficient-memory consolidation. A later
 * checkpoint may share arithmetic units across non-overlapping phases.
 */
module poly_mul4096_runtime_profile_core (
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

    output logic [12:0] preprocessing_count,
    output logic [14:0] forward_butterfly_count,
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

    logic [31:0] modulus_register;

    logic twist_profile_write_enable;
    logic forward_twiddle_profile_write_enable;
    logic inverse_twiddle_profile_write_enable;
    logic inverse_scale_profile_write_enable;

    assign active_modulus =
        modulus_register;

    assign twist_profile_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_TWIST;

    assign forward_twiddle_profile_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_FORWARD_TWIDDLE;

    assign inverse_twiddle_profile_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_INVERSE_TWIDDLE;

    assign inverse_scale_profile_write_enable =
        profile_we
        && !busy
        && profile_bank == PROFILE_BANK_INVERSE_SCALE;

    localparam integer TOTAL_COEFFICIENTS =
        4096;

    localparam integer TOTAL_BUTTERFLIES =
        24576;

    localparam logic [16:0] TOTAL_MODULAR_MULTIPLICATIONS =
        17'd90112;

    typedef enum logic [4:0] {
        STATE_IDLE,

        STATE_PREP_READ_ISSUE,
        STATE_PREP_READ_CAPTURE,
        STATE_PREP_MUL_START,
        STATE_PREP_MUL_WAIT,
        STATE_PREP_WRITEBACK,

        STATE_FORWARD_SCHEDULE_START,
        STATE_FORWARD_READ_ISSUE,
        STATE_FORWARD_READ_CAPTURE,
        STATE_FORWARD_BUTTERFLY_START,
        STATE_FORWARD_BUTTERFLY_WAIT,
        STATE_FORWARD_WRITEBACK,

        STATE_POINTWISE_READ_ISSUE,
        STATE_POINTWISE_READ_CAPTURE,
        STATE_POINTWISE_MUL_START,
        STATE_POINTWISE_MUL_WAIT,
        STATE_POINTWISE_WRITEBACK,

        STATE_INVERSE_SCHEDULE_START,
        STATE_INVERSE_READ_ISSUE,
        STATE_INVERSE_READ_CAPTURE,
        STATE_INVERSE_BUTTERFLY_START,
        STATE_INVERSE_BUTTERFLY_WAIT,
        STATE_INVERSE_WRITEBACK,

        STATE_POST_READ_ISSUE,
        STATE_POST_READ_CAPTURE,
        STATE_POST_MUL_START,
        STATE_POST_MUL_WAIT,
        STATE_POST_WRITEBACK
    } state_t;

    state_t state;

    logic [11:0] coefficient_index;

    /*
     * Coefficient-bank signals.
     */
    logic        bank_a_port_a_enable;
    logic        bank_a_port_a_write_enable;
    logic [11:0] bank_a_port_a_address;
    logic [31:0] bank_a_port_a_write_data;
    logic [31:0] bank_a_port_a_read_data;

    logic        bank_a_port_b_enable;
    logic        bank_a_port_b_write_enable;
    logic [11:0] bank_a_port_b_address;
    logic [31:0] bank_a_port_b_write_data;
    logic [31:0] bank_a_port_b_read_data;

    logic        bank_b_port_a_enable;
    logic        bank_b_port_a_write_enable;
    logic [11:0] bank_b_port_a_address;
    logic [31:0] bank_b_port_a_write_data;
    logic [31:0] bank_b_port_a_read_data;

    logic        bank_b_port_b_enable;
    logic        bank_b_port_b_write_enable;
    logic [11:0] bank_b_port_b_address;
    logic [31:0] bank_b_port_b_write_data;
    logic [31:0] bank_b_port_b_read_data;

    /*
     * Factor and twiddle ROM signals.
     */
    logic twist_enable;
    logic [31:0] twist_read_data;

    logic forward_twiddle_enable;
    logic [31:0] forward_twiddle_read_data;

    logic inverse_twiddle_enable;
    logic [31:0] inverse_twiddle_read_data;

    logic inverse_scale_enable;
    logic [31:0] inverse_scale_read_data;

    /*
     * Dual preprocessing lanes.
     */
    logic prep_start;

    logic prep_a_busy;
    logic prep_a_done;
    logic [31:0] prep_a_result;

    logic prep_b_busy;
    logic prep_b_done;
    logic [31:0] prep_b_result;

    logic [31:0] captured_prep_a;
    logic [31:0] captured_prep_b;
    logic [31:0] captured_twist;

    /*
     * Shared forward-DIF schedule and dual butterfly lanes.
     */
    logic forward_schedule_start;
    logic forward_schedule_advance;

    logic forward_schedule_busy;
    logic forward_schedule_valid;
    logic forward_schedule_done;

    logic [14:0] forward_schedule_operation;
    logic [3:0]  forward_schedule_stage;
    logic [11:0] forward_schedule_group;
    logic [11:0] forward_schedule_j;

    logic [11:0] forward_left_addr;
    logic [11:0] forward_right_addr;
    logic [11:0] forward_twiddle_addr;

    logic forward_butterfly_start;

    logic forward_a_busy;
    logic forward_a_done;
    logic [31:0] forward_a_out_left;
    logic [31:0] forward_a_out_right;

    logic forward_b_busy;
    logic forward_b_done;
    logic [31:0] forward_b_out_left;
    logic [31:0] forward_b_out_right;

    logic [31:0] captured_forward_a_left;
    logic [31:0] captured_forward_a_right;

    logic [31:0] captured_forward_b_left;
    logic [31:0] captured_forward_b_right;

    logic [31:0] captured_forward_twiddle;

    /*
     * One scalar modular multiplier is reused for pointwise
     * multiplication and inverse postprocessing.
     */
    logic scalar_start;
    logic scalar_busy;
    logic scalar_done;
    logic [31:0] scalar_result;

    logic [31:0] captured_scalar_a;
    logic [31:0] captured_scalar_b;

    /*
     * Shared inverse-DIT schedule and one butterfly lane.
     */
    logic inverse_schedule_start;
    logic inverse_schedule_advance;

    logic inverse_schedule_busy;
    logic inverse_schedule_valid;
    logic inverse_schedule_done;

    logic [14:0] inverse_schedule_operation;
    logic [3:0]  inverse_schedule_stage;
    logic [11:0] inverse_schedule_group;
    logic [11:0] inverse_schedule_j;

    logic [11:0] inverse_left_addr;
    logic [11:0] inverse_right_addr;
    logic [11:0] inverse_twiddle_addr;

    logic inverse_butterfly_start;
    logic inverse_butterfly_busy;
    logic inverse_butterfly_done;

    logic [31:0] inverse_out_left;
    logic [31:0] inverse_out_right;

    logic [31:0] captured_inverse_left;
    logic [31:0] captured_inverse_right;
    logic [31:0] captured_inverse_twiddle;

    assign read_a_data =
        bank_a_port_a_read_data;

    assign read_b_data =
        bank_b_port_a_read_data;

    assign twist_enable =
        state == STATE_PREP_READ_ISSUE;

    assign prep_start =
        state == STATE_PREP_MUL_START;

    assign forward_schedule_start =
        state == STATE_FORWARD_SCHEDULE_START;

    assign forward_schedule_advance =
        state == STATE_FORWARD_WRITEBACK;

    assign forward_twiddle_enable =
        state == STATE_FORWARD_READ_ISSUE;

    assign forward_butterfly_start =
        state == STATE_FORWARD_BUTTERFLY_START;

    assign scalar_start =
        state == STATE_POINTWISE_MUL_START
        || state == STATE_POST_MUL_START;

    assign inverse_schedule_start =
        state == STATE_INVERSE_SCHEDULE_START;

    assign inverse_schedule_advance =
        state == STATE_INVERSE_WRITEBACK;

    assign inverse_twiddle_enable =
        state == STATE_INVERSE_READ_ISSUE;

    assign inverse_butterfly_start =
        state == STATE_INVERSE_BUTTERFLY_START;

    assign inverse_scale_enable =
        state == STATE_POST_READ_ISSUE;

    /*
     * Bank A owns the final result. Its ports are multiplexed among all
     * phases and the idle-time external load/read interface.
     */
    always_comb
    begin
        bank_a_port_a_enable =
            1'b0;

        bank_a_port_a_write_enable =
            1'b0;

        bank_a_port_a_address =
            12'd0;

        bank_a_port_a_write_data =
            32'd0;

        bank_a_port_b_enable =
            1'b0;

        bank_a_port_b_write_enable =
            1'b0;

        bank_a_port_b_address =
            12'd0;

        bank_a_port_b_write_data =
            32'd0;

        if (!busy)
        begin
            bank_a_port_a_enable =
                1'b1;

            bank_a_port_a_write_enable =
                load_a_we;

            bank_a_port_a_address =
                load_a_we
                    ? load_a_addr
                    : read_a_addr;

            bank_a_port_a_write_data =
                load_a_data;
        end
        else
        begin
            case (state)
                STATE_PREP_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;
                end

                STATE_PREP_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;

                    bank_a_port_a_write_data =
                        prep_a_result;
                end

                STATE_FORWARD_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        forward_left_addr;

                    bank_a_port_b_enable =
                        1'b1;

                    bank_a_port_b_address =
                        forward_right_addr;
                end

                STATE_FORWARD_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        forward_left_addr;

                    bank_a_port_a_write_data =
                        forward_a_out_left;

                    bank_a_port_b_enable =
                        1'b1;

                    bank_a_port_b_write_enable =
                        1'b1;

                    bank_a_port_b_address =
                        forward_right_addr;

                    bank_a_port_b_write_data =
                        forward_a_out_right;
                end

                STATE_POINTWISE_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;
                end

                STATE_POINTWISE_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;

                    bank_a_port_a_write_data =
                        scalar_result;
                end

                STATE_INVERSE_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        inverse_left_addr;

                    bank_a_port_b_enable =
                        1'b1;

                    bank_a_port_b_address =
                        inverse_right_addr;
                end

                STATE_INVERSE_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        inverse_left_addr;

                    bank_a_port_a_write_data =
                        inverse_out_left;

                    bank_a_port_b_enable =
                        1'b1;

                    bank_a_port_b_write_enable =
                        1'b1;

                    bank_a_port_b_address =
                        inverse_right_addr;

                    bank_a_port_b_write_data =
                        inverse_out_right;
                end

                STATE_POST_READ_ISSUE:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;
                end

                STATE_POST_WRITEBACK:
                begin
                    bank_a_port_a_enable =
                        1'b1;

                    bank_a_port_a_write_enable =
                        1'b1;

                    bank_a_port_a_address =
                        coefficient_index;

                    bank_a_port_a_write_data =
                        scalar_result;
                end

                default:
                begin
                end
            endcase
        end
    end

    /*
     * Bank B participates in preprocessing, the second forward-DIF
     * lane, and pointwise reads. It does not need to be overwritten
     * after the forward transform.
     */
    always_comb
    begin
        bank_b_port_a_enable =
            1'b0;

        bank_b_port_a_write_enable =
            1'b0;

        bank_b_port_a_address =
            12'd0;

        bank_b_port_a_write_data =
            32'd0;

        bank_b_port_b_enable =
            1'b0;

        bank_b_port_b_write_enable =
            1'b0;

        bank_b_port_b_address =
            12'd0;

        bank_b_port_b_write_data =
            32'd0;

        if (!busy)
        begin
            bank_b_port_a_enable =
                1'b1;

            bank_b_port_a_write_enable =
                load_b_we;

            bank_b_port_a_address =
                load_b_we
                    ? load_b_addr
                    : read_b_addr;

            bank_b_port_a_write_data =
                load_b_data;
        end
        else
        begin
            case (state)
                STATE_PREP_READ_ISSUE:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_address =
                        coefficient_index;
                end

                STATE_PREP_WRITEBACK:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_write_enable =
                        1'b1;

                    bank_b_port_a_address =
                        coefficient_index;

                    bank_b_port_a_write_data =
                        prep_b_result;
                end

                STATE_FORWARD_READ_ISSUE:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_address =
                        forward_left_addr;

                    bank_b_port_b_enable =
                        1'b1;

                    bank_b_port_b_address =
                        forward_right_addr;
                end

                STATE_FORWARD_WRITEBACK:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_write_enable =
                        1'b1;

                    bank_b_port_a_address =
                        forward_left_addr;

                    bank_b_port_a_write_data =
                        forward_b_out_left;

                    bank_b_port_b_enable =
                        1'b1;

                    bank_b_port_b_write_enable =
                        1'b1;

                    bank_b_port_b_address =
                        forward_right_addr;

                    bank_b_port_b_write_data =
                        forward_b_out_right;
                end

                STATE_POINTWISE_READ_ISSUE:
                begin
                    bank_b_port_a_enable =
                        1'b1;

                    bank_b_port_a_address =
                        coefficient_index;
                end

                default:
                begin
                end
            endcase
        end
    end

    ntt4096_coeff_bram coefficient_bank_a (
        .clk                 (clk),

        .port_a_enable       (bank_a_port_a_enable),
        .port_a_write_enable (bank_a_port_a_write_enable),
        .port_a_address      (bank_a_port_a_address),
        .port_a_write_data   (bank_a_port_a_write_data),
        .port_a_read_data    (bank_a_port_a_read_data),

        .port_b_enable       (bank_a_port_b_enable),
        .port_b_write_enable (bank_a_port_b_write_enable),
        .port_b_address      (bank_a_port_b_address),
        .port_b_write_data   (bank_a_port_b_write_data),
        .port_b_read_data    (bank_a_port_b_read_data)
    );

    ntt4096_coeff_bram coefficient_bank_b (
        .clk                 (clk),

        .port_a_enable       (bank_b_port_a_enable),
        .port_a_write_enable (bank_b_port_a_write_enable),
        .port_a_address      (bank_b_port_a_address),
        .port_a_write_data   (bank_b_port_a_write_data),
        .port_a_read_data    (bank_b_port_a_read_data),

        .port_b_enable       (bank_b_port_b_enable),
        .port_b_write_enable (bank_b_port_b_write_enable),
        .port_b_address      (bank_b_port_b_address),
        .port_b_write_data   (bank_b_port_b_write_data),
        .port_b_read_data    (bank_b_port_b_read_data)
    );

    ntt4096_profile_bram twist_profile_memory (
        .clk           (clk),

        .read_enable   (twist_enable),
        .read_address  (coefficient_index),
        .read_data     (twist_read_data),

        .write_enable  (twist_profile_write_enable),
        .write_address (profile_addr),
        .write_data    (profile_data)
    );

    ntt4096_profile_bram forward_twiddle_profile_memory (
        .clk           (clk),

        .read_enable   (forward_twiddle_enable),
        .read_address  (forward_twiddle_addr),
        .read_data     (forward_twiddle_read_data),

        .write_enable  (forward_twiddle_profile_write_enable),
        .write_address (profile_addr),
        .write_data    (profile_data)
    );

    ntt4096_profile_bram inverse_twiddle_profile_memory (
        .clk           (clk),

        .read_enable   (inverse_twiddle_enable),
        .read_address  (inverse_twiddle_addr),
        .read_data     (inverse_twiddle_read_data),

        .write_enable  (inverse_twiddle_profile_write_enable),
        .write_address (profile_addr),
        .write_data    (profile_data)
    );

    ntt4096_profile_bram inverse_scale_profile_memory (
        .clk           (clk),

        .read_enable   (inverse_scale_enable),
        .read_address  (coefficient_index),
        .read_data     (inverse_scale_read_data),

        .write_enable  (inverse_scale_profile_write_enable),
        .write_address (profile_addr),
        .write_data    (profile_data)
    );

    modmul_core preprocessing_lane_a (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (prep_start),

        .a       (captured_prep_a),
        .b       (captured_twist),
        .q       (modulus_register),

        .result  (prep_a_result),
        .busy    (prep_a_busy),
        .done    (prep_a_done)
    );

    modmul_core preprocessing_lane_b (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (prep_start),

        .a       (captured_prep_b),
        .b       (captured_twist),
        .q       (modulus_register),

        .result  (prep_b_result),
        .busy    (prep_b_busy),
        .done    (prep_b_done)
    );

    ntt4096_dif_schedule_core forward_schedule (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (forward_schedule_start),
        .advance      (forward_schedule_advance),

        .busy         (forward_schedule_busy),
        .valid        (forward_schedule_valid),
        .done         (forward_schedule_done),

        .operation    (forward_schedule_operation),
        .stage        (forward_schedule_stage),
        .group        (forward_schedule_group),
        .j            (forward_schedule_j),

        .left_addr    (forward_left_addr),
        .right_addr   (forward_right_addr),
        .twiddle_addr (forward_twiddle_addr)
    );

    butterfly_dif_core forward_butterfly_lane_a (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (forward_butterfly_start),

        .a       (captured_forward_a_left),
        .b       (captured_forward_a_right),
        .omega   (captured_forward_twiddle),
        .q       (modulus_register),

        .out_a   (forward_a_out_left),
        .out_b   (forward_a_out_right),
        .busy    (forward_a_busy),
        .done    (forward_a_done)
    );

    butterfly_dif_core forward_butterfly_lane_b (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (forward_butterfly_start),

        .a       (captured_forward_b_left),
        .b       (captured_forward_b_right),
        .omega   (captured_forward_twiddle),
        .q       (modulus_register),

        .out_a   (forward_b_out_left),
        .out_b   (forward_b_out_right),
        .busy    (forward_b_busy),
        .done    (forward_b_done)
    );

    modmul_core scalar_multiplier (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (scalar_start),

        .a       (captured_scalar_a),
        .b       (captured_scalar_b),
        .q       (modulus_register),

        .result  (scalar_result),
        .busy    (scalar_busy),
        .done    (scalar_done)
    );

    ntt4096_schedule_core inverse_schedule (
        .clk          (clk),
        .reset_n      (reset_n),
        .start        (inverse_schedule_start),
        .advance      (inverse_schedule_advance),

        .busy         (inverse_schedule_busy),
        .valid        (inverse_schedule_valid),
        .done         (inverse_schedule_done),

        .operation    (inverse_schedule_operation),
        .stage        (inverse_schedule_stage),
        .group        (inverse_schedule_group),
        .j            (inverse_schedule_j),

        .left_addr    (inverse_left_addr),
        .right_addr   (inverse_right_addr),
        .twiddle_addr (inverse_twiddle_addr)
    );

    butterfly_core inverse_butterfly (
        .clk     (clk),
        .reset_n (reset_n),
        .start   (inverse_butterfly_start),

        .a       (captured_inverse_left),
        .b       (captured_inverse_right),
        .omega   (captured_inverse_twiddle),
        .q       (modulus_register),

        .out_a   (inverse_out_left),
        .out_b   (inverse_out_right),
        .busy    (inverse_butterfly_busy),
        .done    (inverse_butterfly_done)
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

            modulus_register <=
                32'd0;

            profile_ready <=
                1'b0;

            cycles <=
                32'd0;

            multiplication_count <=
                17'd0;

            coefficient_index <=
                12'd0;

            preprocessing_count <=
                13'd0;

            forward_butterfly_count <=
                15'd0;

            pointwise_count <=
                13'd0;

            inverse_butterfly_count <=
                15'd0;

            postprocessing_count <=
                13'd0;

            captured_prep_a <=
                32'd0;

            captured_prep_b <=
                32'd0;

            captured_twist <=
                32'd0;

            captured_forward_a_left <=
                32'd0;

            captured_forward_a_right <=
                32'd0;

            captured_forward_b_left <=
                32'd0;

            captured_forward_b_right <=
                32'd0;

            captured_forward_twiddle <=
                32'd0;

            captured_scalar_a <=
                32'd0;

            captured_scalar_b <=
                32'd0;

            captured_inverse_left <=
                32'd0;

            captured_inverse_right <=
                32'd0;

            captured_inverse_twiddle <=
                32'd0;
        end
        else
        begin
            done <=
                1'b0;

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

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            case (state)
                STATE_IDLE:
                begin
                    if (start && profile_ready)
                    begin
                        state <=
                            STATE_PREP_READ_ISSUE;

                        busy <=
                            1'b1;

                        cycles <=
                            32'd0;

                        multiplication_count <=
                            17'd0;

                        coefficient_index <=
                            12'd0;

                        preprocessing_count <=
                            13'd0;

                        forward_butterfly_count <=
                            15'd0;

                        pointwise_count <=
                            13'd0;

                        inverse_butterfly_count <=
                            15'd0;

                        postprocessing_count <=
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
                    captured_prep_a <=
                        bank_a_port_a_read_data;

                    captured_prep_b <=
                        bank_b_port_a_read_data;

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
                    if (
                        prep_a_done
                        && prep_b_done
                    )
                    begin
                        state <=
                            STATE_PREP_WRITEBACK;
                    end
                end

                STATE_PREP_WRITEBACK:
                begin
                    preprocessing_count <=
                        preprocessing_count + 1'b1;

                    if (
                        coefficient_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_FORWARD_SCHEDULE_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;

                        state <=
                            STATE_PREP_READ_ISSUE;
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
                    captured_forward_a_left <=
                        bank_a_port_a_read_data;

                    captured_forward_a_right <=
                        bank_a_port_b_read_data;

                    captured_forward_b_left <=
                        bank_b_port_a_read_data;

                    captured_forward_b_right <=
                        bank_b_port_b_read_data;

                    captured_forward_twiddle <=
                        forward_twiddle_read_data;

                    state <=
                        STATE_FORWARD_BUTTERFLY_START;
                end

                STATE_FORWARD_BUTTERFLY_START:
                begin
                    state <=
                        STATE_FORWARD_BUTTERFLY_WAIT;
                end

                STATE_FORWARD_BUTTERFLY_WAIT:
                begin
                    if (
                        forward_a_done
                        && forward_b_done
                    )
                    begin
                        state <=
                            STATE_FORWARD_WRITEBACK;
                    end
                end

                STATE_FORWARD_WRITEBACK:
                begin
                    forward_butterfly_count <=
                        forward_butterfly_count + 1'b1;

                    if (
                        forward_butterfly_count
                        == TOTAL_BUTTERFLIES - 1
                    )
                    begin
                        coefficient_index <=
                            12'd0;

                        state <=
                            STATE_POINTWISE_READ_ISSUE;
                    end
                    else
                    begin
                        state <=
                            STATE_FORWARD_READ_ISSUE;
                    end
                end

                STATE_POINTWISE_READ_ISSUE:
                begin
                    state <=
                        STATE_POINTWISE_READ_CAPTURE;
                end

                STATE_POINTWISE_READ_CAPTURE:
                begin
                    captured_scalar_a <=
                        bank_a_port_a_read_data;

                    captured_scalar_b <=
                        bank_b_port_a_read_data;

                    state <=
                        STATE_POINTWISE_MUL_START;
                end

                STATE_POINTWISE_MUL_START:
                begin
                    state <=
                        STATE_POINTWISE_MUL_WAIT;
                end

                STATE_POINTWISE_MUL_WAIT:
                begin
                    if (scalar_done)
                    begin
                        state <=
                            STATE_POINTWISE_WRITEBACK;
                    end
                end

                STATE_POINTWISE_WRITEBACK:
                begin
                    pointwise_count <=
                        pointwise_count + 1'b1;

                    if (
                        coefficient_index
                        == TOTAL_COEFFICIENTS - 1
                    )
                    begin
                        state <=
                            STATE_INVERSE_SCHEDULE_START;
                    end
                    else
                    begin
                        coefficient_index <=
                            coefficient_index + 1'b1;

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
                    captured_inverse_left <=
                        bank_a_port_a_read_data;

                    captured_inverse_right <=
                        bank_a_port_b_read_data;

                    captured_inverse_twiddle <=
                        inverse_twiddle_read_data;

                    state <=
                        STATE_INVERSE_BUTTERFLY_START;
                end

                STATE_INVERSE_BUTTERFLY_START:
                begin
                    state <=
                        STATE_INVERSE_BUTTERFLY_WAIT;
                end

                STATE_INVERSE_BUTTERFLY_WAIT:
                begin
                    if (inverse_butterfly_done)
                    begin
                        state <=
                            STATE_INVERSE_WRITEBACK;
                    end
                end

                STATE_INVERSE_WRITEBACK:
                begin
                    inverse_butterfly_count <=
                        inverse_butterfly_count + 1'b1;

                    if (
                        inverse_butterfly_count
                        == TOTAL_BUTTERFLIES - 1
                    )
                    begin
                        coefficient_index <=
                            12'd0;

                        state <=
                            STATE_POST_READ_ISSUE;
                    end
                    else
                    begin
                        state <=
                            STATE_INVERSE_READ_ISSUE;
                    end
                end

                STATE_POST_READ_ISSUE:
                begin
                    state <=
                        STATE_POST_READ_CAPTURE;
                end

                STATE_POST_READ_CAPTURE:
                begin
                    captured_scalar_a <=
                        bank_a_port_a_read_data;

                    captured_scalar_b <=
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
                    if (scalar_done)
                    begin
                        state <=
                            STATE_POST_WRITEBACK;
                    end
                end

                STATE_POST_WRITEBACK:
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

                        multiplication_count <=
                            TOTAL_MODULAR_MULTIPLICATIONS;
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
            start
            && !profile_ready
        )
        begin
            $display(
                "ERROR: runtime-profile N=4096 core started before profile_commit"
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
                "ERROR: runtime profile changed while polynomial core was busy"
            );

            $fatal(1);
        end

        if (
            profile_commit
            && modulus_register == 32'd0
        )
        begin
            $display(
                "ERROR: runtime profile committed with zero modulus"
            );

            $fatal(1);
        end

        if (
            profile_we
            && (
                (
                    profile_bank == PROFILE_BANK_FORWARD_TWIDDLE
                    || profile_bank == PROFILE_BANK_INVERSE_TWIDDLE
                )
                && profile_addr == 12'd4095
            )
        )
        begin
            $display(
                "ERROR: compact twiddle profile address 4095 is unused"
            );

            $fatal(1);
        end

        if (
            prep_a_done
            ^ prep_b_done
        )
        begin
            $display(
                "ERROR: preprocessing lanes completed on different clocks"
            );

            $fatal(1);
        end

        if (
            forward_a_done
            ^ forward_b_done
        )
        begin
            $display(
                "ERROR: forward-DIF lanes completed on different clocks"
            );

            $fatal(1);
        end

        if (
            state == STATE_PREP_MUL_START
            && (
                prep_a_busy
                || prep_b_busy
            )
        )
        begin
            $display(
                "ERROR: preprocessing start attempted while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_FORWARD_BUTTERFLY_START
            && (
                forward_a_busy
                || forward_b_busy
            )
        )
        begin
            $display(
                "ERROR: forward-DIF start attempted while busy"
            );

            $fatal(1);
        end

        if (
            scalar_start
            && scalar_busy
        )
        begin
            $display(
                "ERROR: scalar modular-multiply start attempted while busy"
            );

            $fatal(1);
        end

        if (
            state == STATE_INVERSE_BUTTERFLY_START
            && inverse_butterfly_busy
        )
        begin
            $display(
                "ERROR: inverse-DIT start attempted while busy"
            );

            $fatal(1);
        end

        if (
            state >= STATE_FORWARD_READ_ISSUE
            && state <= STATE_FORWARD_BUTTERFLY_WAIT
            && (
                !forward_schedule_busy
                || !forward_schedule_valid
            )
        )
        begin
            $display(
                "ERROR: forward-DIF schedule invalid state=%0d operation=%0d",
                state,
                forward_schedule_operation
            );

            $fatal(1);
        end

        if (
            state >= STATE_INVERSE_READ_ISSUE
            && state <= STATE_INVERSE_BUTTERFLY_WAIT
            && (
                !inverse_schedule_busy
                || !inverse_schedule_valid
            )
        )
        begin
            $display(
                "ERROR: inverse-DIT schedule invalid state=%0d operation=%0d",
                state,
                inverse_schedule_operation
            );

            $fatal(1);
        end
    end

`endif

endmodule
