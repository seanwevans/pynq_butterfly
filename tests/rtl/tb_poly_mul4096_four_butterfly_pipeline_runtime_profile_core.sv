`timescale 1ns/1ps

module tb_poly_mul4096_four_butterfly_pipeline_runtime_profile_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLE_WORDS =
        4095;

    localparam integer PROFILE_WORDS =
        16382;

    localparam logic [31:0] LEGACY_CYCLES =
        32'd631810;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [30:0] MU0 =
        31'h4000c001;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    localparam logic [30:0] MU1 =
        31'h40012004;

    localparam logic [1:0] PROFILE_BANK_TWIST =
        2'd0;

    localparam logic [1:0] PROFILE_BANK_FORWARD_TWIDDLE =
        2'd1;

    localparam logic [1:0] PROFILE_BANK_INVERSE_TWIDDLE =
        2'd2;

    localparam logic [1:0] PROFILE_BANK_INVERSE_SCALE =
        2'd3;

    logic clk;
    logic reset_n;
    logic start;

    logic load_a_we;
    logic [11:0] load_a_addr;
    logic [31:0] load_a_data;

    logic load_b_we;
    logic [11:0] load_b_addr;
    logic [31:0] load_b_data;

    logic [11:0] read_a_addr;
    logic [31:0] read_a_data;

    logic [11:0] read_b_addr;
    logic [31:0] read_b_data;

    logic profile_modulus_we;
    logic [31:0] profile_modulus_data;
    logic [30:0] profile_modulus_mu_data;

    logic profile_we;
    logic [1:0] profile_bank;
    logic [11:0] profile_addr;
    logic [31:0] profile_data;

    logic profile_commit;

    logic profile_ready;
    logic [31:0] active_modulus;
    logic [30:0] active_modulus_mu;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [16:0] multiplication_count;

    logic [13:0] preprocessing_count;
    logic [15:0] forward_butterfly_count;
    logic [12:0] pointwise_count;
    logic [14:0] inverse_butterfly_count;
    logic [12:0] postprocessing_count;

    logic [31:0] tower0_a [0:N - 1];
    logic [31:0] tower0_b [0:N - 1];
    logic [31:0] tower0_expected [0:N - 1];

    logic [31:0] tower1_a [0:N - 1];
    logic [31:0] tower1_b [0:N - 1];
    logic [31:0] tower1_expected [0:N - 1];

    logic [31:0] profile0_twist [0:N - 1];
    logic [31:0] profile1_twist [0:N - 1];

    logic [31:0] profile0_forward [0:COMPACT_TWIDDLE_WORDS - 1];
    logic [31:0] profile1_forward [0:COMPACT_TWIDDLE_WORDS - 1];

    logic [31:0] profile0_inverse [0:COMPACT_TWIDDLE_WORDS - 1];
    logic [31:0] profile1_inverse [0:COMPACT_TWIDDLE_WORDS - 1];

    logic [31:0] profile0_scale [0:N - 1];
    logic [31:0] profile1_scale [0:N - 1];

    logic [31:0] first_cycles;

    integer tower_index;
    integer address;
    integer loaded_profile_words;
    integer product_wait_cycles;
    integer checked_coefficients;

    real cycle_speedup;

    poly_mul4096_four_butterfly_pipeline_runtime_profile_core dut (
        .clk                       (clk),
        .reset_n                   (reset_n),
        .start                     (start),

        .load_a_we                 (load_a_we),
        .load_a_addr               (load_a_addr),
        .load_a_data               (load_a_data),

        .load_b_we                 (load_b_we),
        .load_b_addr               (load_b_addr),
        .load_b_data               (load_b_data),

        .read_a_addr               (read_a_addr),
        .read_a_data               (read_a_data),

        .read_b_addr               (read_b_addr),
        .read_b_data               (read_b_data),

        .profile_modulus_we        (profile_modulus_we),
        .profile_modulus_data      (profile_modulus_data),
        .profile_modulus_mu_data   (profile_modulus_mu_data),

        .profile_we                (profile_we),
        .profile_bank              (profile_bank),
        .profile_addr              (profile_addr),
        .profile_data              (profile_data),

        .profile_commit            (profile_commit),

        .profile_ready             (profile_ready),
        .active_modulus            (active_modulus),
        .active_modulus_mu         (active_modulus_mu),

        .busy                      (busy),
        .done                      (done),

        .cycles                    (cycles),
        .multiplication_count      (multiplication_count),

        .preprocessing_count       (preprocessing_count),
        .forward_butterfly_count   (forward_butterfly_count),
        .pointwise_count           (pointwise_count),
        .inverse_butterfly_count   (inverse_butterfly_count),
        .postprocessing_count      (postprocessing_count)
    );

    always #5 clk =
        ~clk;

    task automatic write_profile_word (
        input logic [1:0] selected_bank,
        input logic [11:0] selected_address,
        input logic [31:0] selected_data
    );
        begin
            profile_we =
                1'b1;

            profile_bank =
                selected_bank;

            profile_addr =
                selected_address;

            profile_data =
                selected_data;

            @(posedge clk);
            @(negedge clk);

            loaded_profile_words =
                loaded_profile_words + 1;
        end
    endtask

    task automatic load_runtime_profile (
        input integer selected_tower
    );
        begin
            loaded_profile_words =
                0;

            profile_modulus_we =
                1'b1;

            profile_modulus_data =
                selected_tower == 0
                    ? Q0
                    : Q1;

            profile_modulus_mu_data =
                selected_tower == 0
                    ? MU0
                    : MU1;

            @(posedge clk);
            @(negedge clk);

            profile_modulus_we =
                1'b0;

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                write_profile_word(
                    PROFILE_BANK_TWIST,
                    address[11:0],
                    selected_tower == 0
                        ? profile0_twist[address]
                        : profile1_twist[address]
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLE_WORDS;
                address = address + 1
            )
            begin
                write_profile_word(
                    PROFILE_BANK_FORWARD_TWIDDLE,
                    address[11:0],
                    selected_tower == 0
                        ? profile0_forward[address]
                        : profile1_forward[address]
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLE_WORDS;
                address = address + 1
            )
            begin
                write_profile_word(
                    PROFILE_BANK_INVERSE_TWIDDLE,
                    address[11:0],
                    selected_tower == 0
                        ? profile0_inverse[address]
                        : profile1_inverse[address]
                );
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                write_profile_word(
                    PROFILE_BANK_INVERSE_SCALE,
                    address[11:0],
                    selected_tower == 0
                        ? profile0_scale[address]
                        : profile1_scale[address]
                );
            end

            profile_we =
                1'b0;

            profile_bank =
                2'd0;

            profile_addr =
                12'd0;

            profile_data =
                32'd0;

            profile_commit =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            profile_commit =
                1'b0;

            if (!profile_ready)
            begin
                $fatal(
                    1,
                    "tower=%0d runtime profile did not become ready",
                    selected_tower
                );
            end

            if (
                active_modulus
                !== (
                    selected_tower == 0
                        ? Q0
                        : Q1
                )
            )
            begin
                $fatal(
                    1,
                    "tower=%0d active modulus mismatch",
                    selected_tower
                );
            end

            if (
                active_modulus_mu
                !== (
                    selected_tower == 0
                        ? MU0
                        : MU1
                )
            )
            begin
                $fatal(
                    1,
                    "tower=%0d active reciprocal mismatch",
                    selected_tower
                );
            end

            if (loaded_profile_words != PROFILE_WORDS)
            begin
                $fatal(
                    1,
                    "tower=%0d profile words=%0d expected=%0d",
                    selected_tower,
                    loaded_profile_words,
                    PROFILE_WORDS
                );
            end

            $display(
                "PASS: loaded tower %0d modulus, reciprocal, and %0d profile words",
                selected_tower,
                loaded_profile_words
            );
        end
    endtask

    task automatic load_inputs (
        input integer selected_tower
    );
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                load_a_we =
                    1'b1;

                load_a_addr =
                    address[11:0];

                load_a_data =
                    selected_tower == 0
                        ? tower0_a[address]
                        : tower1_a[address];

                load_b_we =
                    1'b1;

                load_b_addr =
                    address[11:0];

                load_b_data =
                    selected_tower == 0
                        ? tower0_b[address]
                        : tower1_b[address];

                @(posedge clk);
                @(negedge clk);
            end

            load_a_we =
                1'b0;

            load_b_we =
                1'b0;

            $display(
                "PASS: loaded tower %0d OpenFHE operands",
                selected_tower
            );
        end
    endtask

    task automatic execute_product (
        input integer selected_tower
    );
        begin
            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            product_wait_cycles =
                0;

            $display(
                "START: tower %0d four-lane pipelined negacyclic product",
                selected_tower
            );

            while (!done)
            begin
                @(posedge clk);
                @(negedge clk);

                product_wait_cycles =
                    product_wait_cycles + 1;

                if (
                    product_wait_cycles % 5000
                    == 0
                )
                begin
                    $display(
                        "PROGRESS tower=%0d wait=%0d phase=%0d engine=%0d cycles=%0d prep=%0d fwd=%0d point=%0d inv=%0d post=%0d",
                        selected_tower,
                        product_wait_cycles,
                        dut.phase,
                        dut.engine_state,
                        cycles,
                        preprocessing_count,
                        forward_butterfly_count,
                        pointwise_count,
                        inverse_butterfly_count,
                        postprocessing_count
                    );
                end

                if (product_wait_cycles > 30000)
                begin
                    $fatal(
                        1,
                        "tower=%0d watchdog phase=%0d engine=%0d cycles=%0d",
                        selected_tower,
                        dut.phase,
                        dut.engine_state,
                        cycles
                    );
                end
            end

            if (
                preprocessing_count != 14'd8192
                || forward_butterfly_count != 16'd49152
                || pointwise_count != 13'd4096
                || inverse_butterfly_count != 15'd24576
                || postprocessing_count != 13'd4096
                || multiplication_count != 17'd90112
            )
            begin
                $fatal(
                    1,
                    "tower=%0d count mismatch prep=%0d fwd=%0d point=%0d inv=%0d post=%0d mult=%0d",
                    selected_tower,
                    preprocessing_count,
                    forward_butterfly_count,
                    pointwise_count,
                    inverse_butterfly_count,
                    postprocessing_count,
                    multiplication_count
                );
            end

            if (cycles >= LEGACY_CYCLES)
            begin
                $fatal(
                    1,
                    "tower=%0d pipeline cycles=%0d not below legacy=%0d",
                    selected_tower,
                    cycles,
                    LEGACY_CYCLES
                );
            end

            if (cycles > 32'd25000)
            begin
                $fatal(
                    1,
                    "tower=%0d pipeline cycles=%0d exceeded 25000 target",
                    selected_tower,
                    cycles
                );
            end

            $display(
                "PASS: tower %0d controller completed in %0d cycles",
                selected_tower,
                cycles
            );
        end
    endtask

    task automatic compare_result (
        input integer selected_tower
    );
        logic [31:0] expected_value;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                read_a_addr =
                    address[11:0];

                @(posedge clk);
                #1;

                expected_value =
                    selected_tower == 0
                        ? tower0_expected[address]
                        : tower1_expected[address];

                if (read_a_data !== expected_value)
                begin
                    $fatal(
                        1,
                        "tower=%0d address=%0d result=%08x expected=%08x",
                        selected_tower,
                        address,
                        read_a_data,
                        expected_value
                    );
                end

                checked_coefficients =
                    checked_coefficients + 1;
            end

            $display(
                "PASS: tower %0d full product equals OpenFHE",
                selected_tower
            );
        end
    endtask

    initial
    begin
        $readmemh(
            "generated_dual_butterfly_poly/tower0_a.mem",
            tower0_a
        );

        $readmemh(
            "generated_dual_butterfly_poly/tower0_b.mem",
            tower0_b
        );

        $readmemh(
            "generated_dual_butterfly_poly/tower0_expected.mem",
            tower0_expected
        );

        $readmemh(
            "generated_dual_butterfly_poly/tower1_a.mem",
            tower1_a
        );

        $readmemh(
            "generated_dual_butterfly_poly/tower1_b.mem",
            tower1_b
        );

        $readmemh(
            "generated_dual_butterfly_poly/tower1_expected.mem",
            tower1_expected
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile0/twist_factors.mem",
            profile0_twist
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile1/twist_factors.mem",
            profile1_twist
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile0/forward_twiddles.mem",
            profile0_forward
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile1/forward_twiddles.mem",
            profile1_forward
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile0/inverse_twiddles.mem",
            profile0_inverse
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile1/inverse_twiddles.mem",
            profile1_inverse
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile0/inverse_scale_factors.mem",
            profile0_scale
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile1/inverse_scale_factors.mem",
            profile1_scale
        );

        clk =
            1'b0;

        reset_n =
            1'b0;

        start =
            1'b0;

        load_a_we =
            1'b0;

        load_a_addr =
            12'd0;

        load_a_data =
            32'd0;

        load_b_we =
            1'b0;

        load_b_addr =
            12'd0;

        load_b_data =
            32'd0;

        read_a_addr =
            12'd0;

        read_b_addr =
            12'd0;

        profile_modulus_we =
            1'b0;

        profile_modulus_data =
            32'd0;

        profile_modulus_mu_data =
            31'd0;

        profile_we =
            1'b0;

        profile_bank =
            2'd0;

        profile_addr =
            12'd0;

        profile_data =
            32'd0;

        profile_commit =
            1'b0;

        checked_coefficients =
            0;

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n =
            1'b1;

        @(negedge clk);

        for (
            tower_index = 0;
            tower_index < 2;
            tower_index = tower_index + 1
        )
        begin
            load_runtime_profile(tower_index);
            load_inputs(tower_index);
            execute_product(tower_index);
            compare_result(tower_index);

            if (tower_index == 0)
            begin
                first_cycles =
                    cycles;
            end
            else if (cycles !== first_cycles)
            begin
                $fatal(
                    1,
                    "constant-time mismatch q0=%0d q1=%0d",
                    first_cycles,
                    cycles
                );
            end
        end

        if (checked_coefficients != 2 * N)
        begin
            $fatal(
                1,
                "checked=%0d expected=%0d",
                checked_coefficients,
                2 * N
            );
        end

        cycle_speedup =
            LEGACY_CYCLES;

        cycle_speedup =
            cycle_speedup / first_cycles;

        $display(
            "PASS: exact q0/q1 OpenFHE products, %0d checked coefficients",
            checked_coefficients
        );

        $display(
            "Four-lane polynomial cycles: %0d",
            first_cycles
        );

        $display(
            "Legacy polynomial cycles: %0d",
            LEGACY_CYCLES
        );

        $display(
            "Core cycle speedup: %0.3fx",
            cycle_speedup
        );

        $finish;
    end

endmodule
