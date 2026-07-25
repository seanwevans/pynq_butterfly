`timescale 1ns/1ps

/*
 * One-tower N=4096 negacyclic polynomial multiplier using one shared
 * four-lane, II=1 Barrett pipeline for every arithmetic phase.
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
 * Arithmetic phases:
 *
 *     1. twist A
 *     2. twist B
 *     3. forward DIF A
 *     4. forward DIF B
 *     5. pointwise A <- A * B
 *     6. inverse DIT A
 *     7. postscale A
 *
 * Four multiplications or four butterflies are accepted per clock.
 * The same 64 DSP48E1 blocks serve every phase.
 */
module poly_mul4096_four_butterfly_pipeline_runtime_profile_handoff_core (
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

    /* Idle-only four-wide result/refill handoff port. */
    input  logic              handoff_read_valid,
    input  logic [11:0]       handoff_read_base,
    output logic              handoff_read_data_valid,
    output logic [3:0][31:0]  handoff_read_data,

    input  logic              handoff_write_valid,
    input  logic [11:0]       handoff_write_base,
    input  logic [3:0][31:0]  handoff_write_a_data,
    input  logic [3:0][31:0]  handoff_write_b_data,

    input  logic        profile_modulus_we,
    input  logic [31:0] profile_modulus_data,
    input  logic [30:0] profile_modulus_mu_data,

    input  logic        profile_we,
    input  logic [1:0]  profile_bank,
    input  logic [11:0] profile_addr,
    input  logic [31:0] profile_data,

    input  logic        profile_commit,

    output logic        profile_ready,
    output logic [31:0] active_modulus,
    output logic [30:0] active_modulus_mu,

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

    localparam logic [1:0] ARITHMETIC_MODE_SCALAR =
        2'd0;

    localparam logic [1:0] ARITHMETIC_MODE_FORWARD =
        2'd1;

    localparam logic [1:0] ARITHMETIC_MODE_INVERSE =
        2'd2;

    localparam logic [9:0] LAST_LINEAR_ISSUE =
        10'd1023;

    localparam logic [8:0] LAST_NTT_GROUP =
        9'd511;

    localparam logic [16:0] TOTAL_MODULAR_MULTIPLICATIONS =
        17'd90112;

    typedef enum logic [2:0] {
        PHASE_TWIST_A,
        PHASE_TWIST_B,
        PHASE_FORWARD_A,
        PHASE_FORWARD_B,
        PHASE_POINTWISE,
        PHASE_INVERSE_A,
        PHASE_POSTSCALE
    } phase_t;

    typedef enum logic [1:0] {
        ENGINE_IDLE,
        ENGINE_ISSUE,
        ENGINE_DRAIN
    } engine_state_t;

    phase_t phase;
    engine_state_t engine_state;

    logic [31:0] modulus_register;
    logic [30:0] modulus_mu_register;

    assign active_modulus =
        modulus_register;

    assign active_modulus_mu =
        modulus_mu_register;

    wire phase_is_linear =
        phase == PHASE_TWIST_A
        || phase == PHASE_TWIST_B
        || phase == PHASE_POINTWISE
        || phase == PHASE_POSTSCALE;

    wire phase_is_ntt =
        !phase_is_linear;

    wire phase_uses_a =
        phase != PHASE_TWIST_B
        && phase != PHASE_FORWARD_B;

    wire phase_uses_b =
        phase == PHASE_TWIST_B
        || phase == PHASE_FORWARD_B
        || phase == PHASE_POINTWISE;

    wire phase_writes_a =
        phase == PHASE_TWIST_A
        || phase == PHASE_FORWARD_A
        || phase == PHASE_POINTWISE
        || phase == PHASE_INVERSE_A
        || phase == PHASE_POSTSCALE;

    wire phase_writes_b =
        phase == PHASE_TWIST_B
        || phase == PHASE_FORWARD_B;

    wire phase_is_forward =
        phase == PHASE_FORWARD_A
        || phase == PHASE_FORWARD_B;

    wire phase_is_inverse =
        phase == PHASE_INVERSE_A;

    logic [9:0] linear_issue_index;
    logic [9:0] writes_in_linear_phase;

    logic [3:0] current_stage;
    logic [8:0] ntt_issue_group;
    logic [9:0] writes_in_ntt_stage;

    /*
     * Current issue addresses.
     */
    logic [7:0][11:0] ntt_schedule_address;

    ntt4096_four_butterfly_schedule_core ntt_schedule (
        .stage       (current_stage),
        .group_index (ntt_issue_group),
        .address     (ntt_schedule_address)
    );

    logic [12:0] stage_one;
    logic [11:0] twiddle_mask;
    logic [12:0] twiddle_stage_base;
    logic [3:0][11:0] ntt_twiddle_address;

    integer ntt_twiddle_lane;

    always_comb
    begin
        stage_one =
            13'd1 << current_stage;

        twiddle_mask =
            stage_one[11:0] - 1'b1;

        twiddle_stage_base =
            stage_one - 1'b1;

        for (
            ntt_twiddle_lane = 0;
            ntt_twiddle_lane < 4;
            ntt_twiddle_lane = ntt_twiddle_lane + 1
        )
        begin
            ntt_twiddle_address[ntt_twiddle_lane] =
                twiddle_stage_base[11:0]
                + (
                    ntt_schedule_address[
                        2 * ntt_twiddle_lane
                    ]
                    & twiddle_mask
                );
        end
    end

    logic [11:0] linear_group_base;
    logic        linear_upper_half;
    logic [7:0][11:0] linear_group_address;
    logic [3:0][11:0] linear_factor_address;

    integer linear_address_index;

    /*
     * Four arithmetic lanes update one half of an eight-bank group.
     *
     * Do not alternate lower and upper halves of the same group on
     * consecutive clocks. Each writeback preserves the untouched half
     * from the corresponding read. Consecutive lower/upper launches
     * would therefore make the upper-half write restore stale lower-half
     * coefficients.
     *
     * Instead:
     *
     *     issues   0..511: lower halves of groups 0..511
     *     issues 512..1023: upper halves of groups 0..511
     *
     * By the time an upper half is read, the matching lower-half write
     * completed hundreds of clocks earlier.
     */
    always_comb
    begin
        linear_group_base = {
            linear_issue_index[8:0],
            3'b000
        };

        linear_upper_half =
            linear_issue_index[9];

        for (
            linear_address_index = 0;
            linear_address_index < 8;
            linear_address_index = linear_address_index + 1
        )
        begin
            linear_group_address[linear_address_index] =
                linear_group_base
                + linear_address_index[11:0];
        end

        for (
            linear_address_index = 0;
            linear_address_index < 4;
            linear_address_index = linear_address_index + 1
        )
        begin
            linear_factor_address[linear_address_index] =
                linear_group_base
                + (
                    linear_upper_half
                        ? 12'd4
                        : 12'd0
                )
                + linear_address_index[11:0];
        end
    end

    wire issue_valid =
        busy
        && engine_state == ENGINE_ISSUE;

    /*
     * Runtime profile tables. Each table is replicated into two
     * true-dual-port BRAM copies, yielding four synchronous read ports.
     */
    logic [3:0][31:0] twist_read_data;
    logic [3:0][31:0] forward_twiddle_read_data;
    logic [3:0][31:0] inverse_twiddle_read_data;
    logic [3:0][31:0] scale_read_data;

    logic twist_read_enable;
    logic forward_twiddle_read_enable;
    logic inverse_twiddle_read_enable;
    logic scale_read_enable;

    assign twist_read_enable =
        issue_valid
        && (
            phase == PHASE_TWIST_A
            || phase == PHASE_TWIST_B
        );

    assign forward_twiddle_read_enable =
        issue_valid
        && phase_is_forward;

    assign inverse_twiddle_read_enable =
        issue_valid
        && phase_is_inverse;

    assign scale_read_enable =
        issue_valid
        && phase == PHASE_POSTSCALE;

    ntt4096_profile_bram_four_read twist_memory (
        .clk           (clk),

        .write_enable  (
            profile_we
            && !busy
            && profile_bank == PROFILE_BANK_TWIST
        ),

        .write_address (profile_addr),
        .write_data    (profile_data),

        .read_enable   (twist_read_enable),
        .read_address  (linear_factor_address),
        .read_data     (twist_read_data)
    );

    ntt4096_profile_bram_four_read forward_twiddle_memory (
        .clk           (clk),

        .write_enable  (
            profile_we
            && !busy
            && profile_bank == PROFILE_BANK_FORWARD_TWIDDLE
        ),

        .write_address (profile_addr),
        .write_data    (profile_data),

        .read_enable   (forward_twiddle_read_enable),
        .read_address  (ntt_twiddle_address),
        .read_data     (forward_twiddle_read_data)
    );

    ntt4096_profile_bram_four_read inverse_twiddle_memory (
        .clk           (clk),

        .write_enable  (
            profile_we
            && !busy
            && profile_bank == PROFILE_BANK_INVERSE_TWIDDLE
        ),

        .write_address (profile_addr),
        .write_data    (profile_data),

        .read_enable   (inverse_twiddle_read_enable),
        .read_address  (ntt_twiddle_address),
        .read_data     (inverse_twiddle_read_data)
    );

    ntt4096_profile_bram_four_read inverse_scale_memory (
        .clk           (clk),

        .write_enable  (
            profile_we
            && !busy
            && profile_bank == PROFILE_BANK_INVERSE_SCALE
        ),

        .write_address (profile_addr),
        .write_data    (profile_data),

        .read_enable   (scale_read_enable),
        .read_address  (linear_factor_address),
        .read_data     (scale_read_data)
    );

    /*
     * Eight-bank coefficient stores.
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

    logic unused_b_handoff_read_data_valid;
    logic [3:0][31:0] unused_b_handoff_read_data;

    integer inspect_index;

    always_comb
    begin
        for (
            inspect_index = 0;
            inspect_index < 8;
            inspect_index = inspect_index + 1
        )
        begin
            inspect_a_address[inspect_index] =
                read_a_addr ^ inspect_index[11:0];

            inspect_b_address[inspect_index] =
                read_b_addr ^ inspect_index[11:0];
        end

        a_store_read_valid =
            1'b0;

        a_store_read_address =
            '0;

        b_store_read_valid =
            1'b0;

        b_store_read_address =
            '0;

        if (!busy)
        begin
            a_store_read_valid =
                1'b1;

            a_store_read_address =
                inspect_a_address;

            b_store_read_valid =
                1'b1;

            b_store_read_address =
                inspect_b_address;
        end
        else if (issue_valid)
        begin
            if (phase_is_linear)
            begin
                if (phase_uses_a)
                begin
                    a_store_read_valid =
                        1'b1;

                    a_store_read_address =
                        linear_group_address;
                end

                if (phase_uses_b)
                begin
                    b_store_read_valid =
                        1'b1;

                    b_store_read_address =
                        linear_group_address;
                end
            end
            else
            begin
                if (phase_uses_a)
                begin
                    a_store_read_valid =
                        1'b1;

                    a_store_read_address =
                        ntt_schedule_address;
                end

                if (phase_uses_b)
                begin
                    b_store_read_valid =
                        1'b1;

                    b_store_read_address =
                        ntt_schedule_address;
                end
            end
        end
    end

    assign read_a_data =
        a_store_read_data[0];

    assign read_b_data =
        b_store_read_data[0];

    ntt4096_eight_bank_coeff_store_runtime_handoff4 coefficient_store_a (
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
        .write_data      (a_store_write_data),

        .handoff_read_valid (
            handoff_read_valid
            && !busy
        ),
        .handoff_read_base       (handoff_read_base),
        .handoff_read_data_valid (handoff_read_data_valid),
        .handoff_read_data       (handoff_read_data),

        .handoff_write_valid (
            handoff_write_valid
            && !busy
        ),
        .handoff_write_base  (handoff_write_base),
        .handoff_write_data  (handoff_write_a_data)
    );

    ntt4096_eight_bank_coeff_store_runtime_handoff4 coefficient_store_b (
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
        .write_data      (b_store_write_data),

        .handoff_read_valid      (1'b0),
        .handoff_read_base       (12'd0),
        .handoff_read_data_valid (unused_b_handoff_read_data_valid),
        .handoff_read_data       (unused_b_handoff_read_data),

        .handoff_write_valid (
            handoff_write_valid
            && !busy
        ),
        .handoff_write_base  (handoff_write_base),
        .handoff_write_data  (handoff_write_b_data)
    );

    /*
     * One-cycle synchronous read alignment.
     */
    phase_t issue_phase_q;
    logic issue_valid_q;
    logic issue_upper_half_q;
    logic [11:0] issue_group_base_q;
    logic [7:0][11:0] issue_ntt_address_q;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            issue_phase_q <=
                PHASE_TWIST_A;

            issue_valid_q <=
                1'b0;

            issue_upper_half_q <=
                1'b0;

            issue_group_base_q <=
                12'd0;

            issue_ntt_address_q <=
                '0;
        end
        else
        begin
            issue_valid_q <=
                issue_valid;

            if (issue_valid)
            begin
                issue_phase_q <=
                    phase;

                issue_upper_half_q <=
                    linear_upper_half;

                issue_group_base_q <=
                    linear_group_base;

                issue_ntt_address_q <=
                    ntt_schedule_address;
            end
        end
    end

    wire issue_phase_is_linear =
        issue_phase_q == PHASE_TWIST_A
        || issue_phase_q == PHASE_TWIST_B
        || issue_phase_q == PHASE_POINTWISE
        || issue_phase_q == PHASE_POSTSCALE;

    wire issue_phase_uses_a =
        issue_phase_q != PHASE_TWIST_B
        && issue_phase_q != PHASE_FORWARD_B;

    wire issue_phase_uses_b =
        issue_phase_q == PHASE_TWIST_B
        || issue_phase_q == PHASE_FORWARD_B
        || issue_phase_q == PHASE_POINTWISE;

    wire coefficient_inputs_valid =
        (
            !issue_phase_uses_a
            || a_store_read_data_valid
        )
        && (
            !issue_phase_uses_b
            || b_store_read_data_valid
        );

    wire arithmetic_input_valid =
        issue_valid_q
        && coefficient_inputs_valid;

    logic [1:0] arithmetic_mode;
    logic [3:0][31:0] arithmetic_input_a;
    logic [3:0][31:0] arithmetic_input_b;
    logic [3:0][31:0] arithmetic_input_omega;

    integer arithmetic_lane;

    always_comb
    begin
        arithmetic_mode =
            ARITHMETIC_MODE_SCALAR;

        arithmetic_input_a =
            '0;

        arithmetic_input_b =
            '0;

        arithmetic_input_omega =
            '0;

        for (
            arithmetic_lane = 0;
            arithmetic_lane < 4;
            arithmetic_lane = arithmetic_lane + 1
        )
        begin
            if (issue_phase_is_linear)
            begin
                if (issue_phase_q == PHASE_TWIST_A)
                begin
                    arithmetic_input_a[arithmetic_lane] =
                        twist_read_data[arithmetic_lane];

                    arithmetic_input_b[arithmetic_lane] =
                        a_store_read_data[
                            (
                                issue_upper_half_q
                                    ? 4
                                    : 0
                            )
                            + arithmetic_lane
                        ];
                end
                else if (issue_phase_q == PHASE_TWIST_B)
                begin
                    arithmetic_input_a[arithmetic_lane] =
                        twist_read_data[arithmetic_lane];

                    arithmetic_input_b[arithmetic_lane] =
                        b_store_read_data[
                            (
                                issue_upper_half_q
                                    ? 4
                                    : 0
                            )
                            + arithmetic_lane
                        ];
                end
                else if (issue_phase_q == PHASE_POINTWISE)
                begin
                    arithmetic_input_a[arithmetic_lane] =
                        b_store_read_data[
                            (
                                issue_upper_half_q
                                    ? 4
                                    : 0
                            )
                            + arithmetic_lane
                        ];

                    arithmetic_input_b[arithmetic_lane] =
                        a_store_read_data[
                            (
                                issue_upper_half_q
                                    ? 4
                                    : 0
                            )
                            + arithmetic_lane
                        ];
                end
                else
                begin
                    arithmetic_input_a[arithmetic_lane] =
                        scale_read_data[arithmetic_lane];

                    arithmetic_input_b[arithmetic_lane] =
                        a_store_read_data[
                            (
                                issue_upper_half_q
                                    ? 4
                                    : 0
                            )
                            + arithmetic_lane
                        ];
                end
            end
            else
            begin
                arithmetic_mode =
                    issue_phase_q == PHASE_INVERSE_A
                        ? ARITHMETIC_MODE_INVERSE
                        : ARITHMETIC_MODE_FORWARD;

                arithmetic_input_a[arithmetic_lane] =
                    issue_phase_q == PHASE_FORWARD_B
                        ? b_store_read_data[
                            2 * arithmetic_lane
                        ]
                        : a_store_read_data[
                            2 * arithmetic_lane
                        ];

                arithmetic_input_b[arithmetic_lane] =
                    issue_phase_q == PHASE_FORWARD_B
                        ? b_store_read_data[
                            2 * arithmetic_lane + 1
                        ]
                        : a_store_read_data[
                            2 * arithmetic_lane + 1
                        ];

                arithmetic_input_omega[arithmetic_lane] =
                    issue_phase_q == PHASE_INVERSE_A
                        ? inverse_twiddle_read_data[
                            arithmetic_lane
                        ]
                        : forward_twiddle_read_data[
                            arithmetic_lane
                        ];
            end
        end
    end

    logic             arithmetic_output_valid;
    logic [3:0][31:0] arithmetic_output_a;
    logic [3:0][31:0] arithmetic_output_b;

    poly_mul4096_four_lane_arithmetic_core arithmetic (
        .clk          (clk),
        .reset_n      (reset_n),

        .input_valid  (arithmetic_input_valid),
        .mode         (arithmetic_mode),

        .input_a      (arithmetic_input_a),
        .input_b      (arithmetic_input_b),
        .input_omega  (arithmetic_input_omega),

        .q            (modulus_register),
        .mu           (modulus_mu_register),

        .output_valid (arithmetic_output_valid),
        .output_a     (arithmetic_output_a),
        .output_b     (arithmetic_output_b)
    );

    /*
     * Metadata is captured with the arithmetic input and delayed through
     * nine registers. The butterfly wrapper reports output_valid nine
     * clocks after input_valid, so writeback must use slot nine.
     *
     * This matches the ten-register address path in the already-proven
     * standalone four-butterfly transform engine:
     *
     *     capture slot 0 on launch
     *     consume slot 9 with arithmetic_output_valid
     */
    phase_t meta_phase [0:9];
    logic meta_upper_half [0:9];
    logic [11:0] meta_group_base [0:9];
    logic [7:0][11:0] meta_ntt_address [0:9];
    logic [7:0][31:0] meta_a_data [0:9];
    logic [7:0][31:0] meta_b_data [0:9];

    integer meta_index;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            for (
                meta_index = 0;
                meta_index < 10;
                meta_index = meta_index + 1
            )
            begin
                meta_phase[meta_index] <=
                    PHASE_TWIST_A;

                meta_upper_half[meta_index] <=
                    1'b0;

                meta_group_base[meta_index] <=
                    12'd0;

                meta_ntt_address[meta_index] <=
                    '0;

                meta_a_data[meta_index] <=
                    '0;

                meta_b_data[meta_index] <=
                    '0;
            end
        end
        else
        begin
            if (arithmetic_input_valid)
            begin
                meta_phase[0] <=
                    issue_phase_q;

                meta_upper_half[0] <=
                    issue_upper_half_q;

                meta_group_base[0] <=
                    issue_group_base_q;

                meta_ntt_address[0] <=
                    issue_ntt_address_q;

                meta_a_data[0] <=
                    a_store_read_data;

                meta_b_data[0] <=
                    b_store_read_data;
            end

            for (
                meta_index = 1;
                meta_index < 10;
                meta_index = meta_index + 1
            )
            begin
                meta_phase[meta_index] <=
                    meta_phase[meta_index - 1];

                meta_upper_half[meta_index] <=
                    meta_upper_half[meta_index - 1];

                meta_group_base[meta_index] <=
                    meta_group_base[meta_index - 1];

                meta_ntt_address[meta_index] <=
                    meta_ntt_address[meta_index - 1];

                meta_a_data[meta_index] <=
                    meta_a_data[meta_index - 1];

                meta_b_data[meta_index] <=
                    meta_b_data[meta_index - 1];
            end
        end
    end

    // Plain vector, not phase_t: assigning an unpacked-array element
    // to an enum needs a cast that some Icarus builds reject.
    // Comparisons against phase_t constants still work.
    logic [2:0] output_phase;
    logic output_phase_is_linear;
    logic output_phase_writes_a;
    logic output_phase_writes_b;

    assign output_phase =
        meta_phase[9];

    assign output_phase_is_linear =
        output_phase == PHASE_TWIST_A
        || output_phase == PHASE_TWIST_B
        || output_phase == PHASE_POINTWISE
        || output_phase == PHASE_POSTSCALE;

    assign output_phase_writes_a =
        output_phase == PHASE_TWIST_A
        || output_phase == PHASE_FORWARD_A
        || output_phase == PHASE_POINTWISE
        || output_phase == PHASE_INVERSE_A
        || output_phase == PHASE_POSTSCALE;

    assign output_phase_writes_b =
        output_phase == PHASE_TWIST_B
        || output_phase == PHASE_FORWARD_B;

    integer write_index;

    always_comb
    begin
        a_store_write_valid =
            arithmetic_output_valid
            && output_phase_writes_a;

        b_store_write_valid =
            arithmetic_output_valid
            && output_phase_writes_b;

        a_store_write_address =
            '0;

        a_store_write_data =
            '0;

        b_store_write_address =
            '0;

        b_store_write_data =
            '0;

        if (output_phase_is_linear)
        begin
            for (
                write_index = 0;
                write_index < 8;
                write_index = write_index + 1
            )
            begin
                a_store_write_address[write_index] =
                    meta_group_base[9]
                    + write_index[11:0];

                b_store_write_address[write_index] =
                    meta_group_base[9]
                    + write_index[11:0];

                a_store_write_data[write_index] =
                    meta_a_data[9][write_index];

                b_store_write_data[write_index] =
                    meta_b_data[9][write_index];
            end

            for (
                write_index = 0;
                write_index < 4;
                write_index = write_index + 1
            )
            begin
                if (output_phase_writes_a)
                begin
                    a_store_write_data[
                        (
                            meta_upper_half[9]
                                ? 4
                                : 0
                        )
                        + write_index
                    ] =
                        arithmetic_output_a[write_index];
                end

                if (output_phase_writes_b)
                begin
                    b_store_write_data[
                        (
                            meta_upper_half[9]
                                ? 4
                                : 0
                        )
                        + write_index
                    ] =
                        arithmetic_output_a[write_index];
                end
            end
        end
        else
        begin
            a_store_write_address =
                meta_ntt_address[9];

            b_store_write_address =
                meta_ntt_address[9];

            for (
                write_index = 0;
                write_index < 4;
                write_index = write_index + 1
            )
            begin
                if (output_phase_writes_a)
                begin
                    a_store_write_data[
                        2 * write_index
                    ] =
                        arithmetic_output_a[write_index];

                    a_store_write_data[
                        2 * write_index + 1
                    ] =
                        arithmetic_output_b[write_index];
                end

                if (output_phase_writes_b)
                begin
                    b_store_write_data[
                        2 * write_index
                    ] =
                        arithmetic_output_a[write_index];

                    b_store_write_data[
                        2 * write_index + 1
                    ] =
                        arithmetic_output_b[write_index];
                end
            end
        end
    end

    /*
     * Controller.
     *
     * Phase transitions are written inline. This avoids simulator-specific
     * parsing of enum-typed task ports and keeps every state update visible
     * in the single sequential process.
     */

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            phase <=
                PHASE_TWIST_A;

            engine_state <=
                ENGINE_IDLE;

            modulus_register <=
                32'd0;

            modulus_mu_register <=
                31'd0;

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

            linear_issue_index <=
                10'd0;

            writes_in_linear_phase <=
                10'd0;

            current_stage <=
                4'd0;

            ntt_issue_group <=
                9'd0;

            writes_in_ntt_stage <=
                10'd0;
        end
        else
        begin
            done <=
                1'b0;

            if (!busy && profile_modulus_we)
            begin
                modulus_register <=
                    profile_modulus_data;

                modulus_mu_register <=
                    profile_modulus_mu_data;

                profile_ready <=
                    1'b0;
            end

            if (!busy && profile_commit)
            begin
                profile_ready <=
                    modulus_register != 32'd0
                    && modulus_mu_register != 31'd0;
            end

            if (busy)
            begin
                cycles <=
                    cycles + 1'b1;
            end

            if (
                busy
                && engine_state == ENGINE_ISSUE
            )
            begin
                if (phase_is_linear)
                begin
                    if (
                        linear_issue_index
                        == LAST_LINEAR_ISSUE
                    )
                    begin
                        linear_issue_index <=
                            10'd0;

                        engine_state <=
                            ENGINE_DRAIN;
                    end
                    else
                    begin
                        linear_issue_index <=
                            linear_issue_index + 1'b1;
                    end
                end
                else
                begin
                    if (
                        ntt_issue_group
                        == LAST_NTT_GROUP
                    )
                    begin
                        ntt_issue_group <=
                            9'd0;

                        engine_state <=
                            ENGINE_DRAIN;
                    end
                    else
                    begin
                        ntt_issue_group <=
                            ntt_issue_group + 1'b1;
                    end
                end
            end

            if (arithmetic_output_valid)
            begin
                multiplication_count <=
                    multiplication_count + 3'd4;

                case (output_phase)
                    PHASE_TWIST_A,
                    PHASE_TWIST_B:
                    begin
                        preprocessing_count <=
                            preprocessing_count + 3'd4;
                    end

                    PHASE_FORWARD_A,
                    PHASE_FORWARD_B:
                    begin
                        forward_butterfly_count <=
                            forward_butterfly_count + 3'd4;
                    end

                    PHASE_POINTWISE:
                    begin
                        pointwise_count <=
                            pointwise_count + 3'd4;
                    end

                    PHASE_INVERSE_A:
                    begin
                        inverse_butterfly_count <=
                            inverse_butterfly_count + 3'd4;
                    end

                    PHASE_POSTSCALE:
                    begin
                        postprocessing_count <=
                            postprocessing_count + 3'd4;
                    end

                    default:
                    begin
                    end
                endcase

                if (output_phase_is_linear)
                begin
                    if (
                        writes_in_linear_phase
                        == LAST_LINEAR_ISSUE
                    )
                    begin
                        writes_in_linear_phase <=
                            10'd0;

                        case (output_phase)
                            PHASE_TWIST_A:
                            begin
                                phase <=
                                    PHASE_TWIST_B;

                                linear_issue_index <=
                                    10'd0;

                                writes_in_linear_phase <=
                                    10'd0;

                                engine_state <=
                                    ENGINE_ISSUE;
                            end

                            PHASE_TWIST_B:
                            begin
                                phase <=
                                    PHASE_FORWARD_A;

                                current_stage <=
                                    4'd11;

                                ntt_issue_group <=
                                    9'd0;

                                writes_in_ntt_stage <=
                                    10'd0;

                                engine_state <=
                                    ENGINE_ISSUE;
                            end

                            PHASE_POINTWISE:
                            begin
                                phase <=
                                    PHASE_INVERSE_A;

                                current_stage <=
                                    4'd0;

                                ntt_issue_group <=
                                    9'd0;

                                writes_in_ntt_stage <=
                                    10'd0;

                                engine_state <=
                                    ENGINE_ISSUE;
                            end

                            PHASE_POSTSCALE:
                            begin
                                multiplication_count <=
                                    TOTAL_MODULAR_MULTIPLICATIONS;

                                busy <=
                                    1'b0;

                                done <=
                                    1'b1;

                                engine_state <=
                                    ENGINE_IDLE;
                            end

                            default:
                            begin
                            end
                        endcase
                    end
                    else
                    begin
                        writes_in_linear_phase <=
                            writes_in_linear_phase + 1'b1;
                    end
                end
                else
                begin
                    if (
                        writes_in_ntt_stage
                        == 10'd511
                    )
                    begin
                        writes_in_ntt_stage <=
                            10'd0;

                        if (output_phase == PHASE_INVERSE_A)
                        begin
                            if (current_stage == 4'd11)
                            begin
                                phase <=
                                    PHASE_POSTSCALE;

                                linear_issue_index <=
                                    10'd0;

                                writes_in_linear_phase <=
                                    10'd0;

                                engine_state <=
                                    ENGINE_ISSUE;
                            end
                            else
                            begin
                                current_stage <=
                                    current_stage + 1'b1;

                                ntt_issue_group <=
                                    9'd0;

                                engine_state <=
                                    ENGINE_ISSUE;
                            end
                        end
                        else
                        begin
                            if (current_stage == 4'd0)
                            begin
                                if (
                                    output_phase
                                    == PHASE_FORWARD_A
                                )
                                begin
                                    phase <=
                                        PHASE_FORWARD_B;

                                    current_stage <=
                                        4'd11;

                                    ntt_issue_group <=
                                        9'd0;

                                    writes_in_ntt_stage <=
                                        10'd0;

                                    engine_state <=
                                        ENGINE_ISSUE;
                                end
                                else
                                begin
                                    phase <=
                                        PHASE_POINTWISE;

                                    linear_issue_index <=
                                        10'd0;

                                    writes_in_linear_phase <=
                                        10'd0;

                                    engine_state <=
                                        ENGINE_ISSUE;
                                end
                            end
                            else
                            begin
                                current_stage <=
                                    current_stage - 1'b1;

                                ntt_issue_group <=
                                    9'd0;

                                engine_state <=
                                    ENGINE_ISSUE;
                            end
                        end
                    end
                    else
                    begin
                        writes_in_ntt_stage <=
                            writes_in_ntt_stage + 1'b1;
                    end
                end
            end

            if (
                !busy
                && start
                && profile_ready
            )
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

                phase <=
                    PHASE_TWIST_A;

                linear_issue_index <=
                    10'd0;

                writes_in_linear_phase <=
                    10'd0;

                engine_state <=
                    ENGINE_ISSUE;
            end
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            busy
            && (
                handoff_read_valid
                || handoff_write_valid
            )
        )
        begin
            $display(
                "ERROR: idle-only handoff port used while arithmetic busy"
            );

            $fatal(1);
        end

        if (
            busy
            && (
                profile_modulus_we
                || profile_we
                || profile_commit
                || load_a_we
                || load_b_we
            )
        )
        begin
            $display(
                "ERROR: runtime memory/profile update attempted while busy"
            );

            $fatal(1);
        end

        if (
            start
            && !busy
            && !profile_ready
        )
        begin
            $display(
                "ERROR: product start attempted before profile commit"
            );

            $fatal(1);
        end

        if (
            arithmetic_input_valid
            && !coefficient_inputs_valid
        )
        begin
            $display(
                "ERROR: arithmetic launch without coefficient data"
            );

            $fatal(1);
        end
    end

`endif

endmodule
