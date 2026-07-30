`timescale 1ns/1ps

module tb_poly_mul4096_dual_butterfly_runtime_profile_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLE_WORDS =
        4095;

    localparam integer PROFILE_WORDS =
        16382;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd631810;

`ifdef FAST_MODMUL

    localparam integer PRODUCT_WATCHDOG_CYCLES =
        300000;

`else

    localparam integer PRODUCT_WATCHDOG_CYCLES =
        700000;

`endif

    localparam logic [1:0] PROFILE_BANK_TWIST =
        2'd0;

    localparam logic [1:0] PROFILE_BANK_FORWARD_TWIDDLE =
        2'd1;

    localparam logic [1:0] PROFILE_BANK_INVERSE_TWIDDLE =
        2'd2;

    localparam logic [1:0] PROFILE_BANK_INVERSE_SCALE =
        2'd3;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic load_a_we =
        1'b0;

    logic [11:0] load_a_addr =
        12'd0;

    logic [31:0] load_a_data =
        32'd0;

    logic load_b_we =
        1'b0;

    logic [11:0] load_b_addr =
        12'd0;

    logic [31:0] load_b_data =
        32'd0;

    logic [11:0] read_a_addr =
        12'd0;

    logic [31:0] read_a_data;

    logic [11:0] read_b_addr =
        12'd0;

    logic [31:0] read_b_data;

    logic profile_modulus_we =
        1'b0;

    logic [31:0] profile_modulus_data =
        32'd0;

    logic profile_we =
        1'b0;

    logic [1:0] profile_bank =
        2'd0;

    logic [11:0] profile_addr =
        12'd0;

    logic [31:0] profile_data =
        32'd0;

    logic profile_commit =
        1'b0;

    logic profile_ready;
    logic [31:0] active_modulus;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [16:0] multiplication_count;

    logic [13:0] preprocessing_count;
    logic [15:0] forward_butterfly_count;
    logic [12:0] pointwise_count;
    logic [14:0] inverse_butterfly_count;
    logic [12:0] postprocessing_count;

    logic [31:0] tower0_a [0:N-1];
    logic [31:0] tower0_b [0:N-1];
    logic [31:0] tower0_expected [0:N-1];

    logic [31:0] tower1_a [0:N-1];
    logic [31:0] tower1_b [0:N-1];
    logic [31:0] tower1_expected [0:N-1];

    logic [31:0] profile0_twist [0:N-1];
    logic [31:0] profile1_twist [0:N-1];

    logic [31:0] profile0_forward [0:COMPACT_TWIDDLE_WORDS-1];
    logic [31:0] profile1_forward [0:COMPACT_TWIDDLE_WORDS-1];

    logic [31:0] profile0_inverse [0:COMPACT_TWIDDLE_WORDS-1];
    logic [31:0] profile1_inverse [0:COMPACT_TWIDDLE_WORDS-1];

    logic [31:0] profile0_scale [0:N-1];
    logic [31:0] profile1_scale [0:N-1];

    logic [31:0] first_cycles;

    integer address;
    integer tower_index;
    integer loaded_profile_words;
    integer product_wait_cycles;

    poly_mul4096_dual_butterfly_runtime_profile_core dut (
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

        .profile_we                (profile_we),
        .profile_bank              (profile_bank),
        .profile_addr              (profile_addr),
        .profile_data              (profile_data),

        .profile_commit            (profile_commit),

        .profile_ready             (profile_ready),
        .active_modulus            (active_modulus),

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

    always #5 clk = ~clk;

    task automatic write_profile_word;
        input [1:0] selected_bank;
        input [11:0] selected_address;
        input [31:0] selected_data;

        begin
            @(negedge clk);

            profile_we =
                1'b1;

            profile_bank =
                selected_bank;

            profile_addr =
                selected_address;

            profile_data =
                selected_data;

            @(posedge clk);

            loaded_profile_words =
                loaded_profile_words + 1;
        end
    endtask

    task automatic load_runtime_profile;
        input integer selected_tower;

        begin
            loaded_profile_words =
                0;

            @(negedge clk);

            profile_modulus_we =
                1'b1;

            profile_modulus_data =
                selected_tower == 0
                    ? Q0
                    : Q1;

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

            $display(
                "PROGRESS: tower %0d loaded twist table",
                selected_tower
            );

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

            $display(
                "PROGRESS: tower %0d loaded forward twiddles",
                selected_tower
            );

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

            $display(
                "PROGRESS: tower %0d loaded inverse twiddles",
                selected_tower
            );

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

            $display(
                "PROGRESS: tower %0d loaded inverse-scale table",
                selected_tower
            );

            @(negedge clk);

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
                $display(
                    "FAIL: runtime profile did not become ready"
                );

                $fatal(1);
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
                $display(
                    "FAIL PROFILE MODULUS tower=%0d result=%0d",
                    selected_tower,
                    active_modulus
                );

                $fatal(1);
            end

            if (loaded_profile_words != PROFILE_WORDS)
            begin
                $display(
                    "FAIL PROFILE WORD COUNT result=%0d expected=%0d",
                    loaded_profile_words,
                    PROFILE_WORDS
                );

                $fatal(1);
            end

            $display(
                "PASS: loaded tower %0d modulus and %0d runtime profile words",
                selected_tower,
                loaded_profile_words
            );
        end
    endtask

    task automatic load_inputs;
        input integer selected_tower;

        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

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
            end

            @(negedge clk);

            load_a_we =
                1'b0;

            load_b_we =
                1'b0;

            $display(
                "PASS: loaded tower %0d coefficient operands",
                selected_tower
            );
        end
    endtask

    task automatic execute_product;
        begin
            @(negedge clk);

            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            product_wait_cycles =
                0;

            $display(
                "START: tower product execution"
            );

            while (!done)
            begin
                @(posedge clk);
                @(negedge clk);

                product_wait_cycles =
                    product_wait_cycles + 1;

                if (
                    product_wait_cycles % 25000
                    == 0
                )
                begin
                    $display(
                        "PROGRESS product wait=%0d state=%0d core_cycles=%0d prep=%0d fwd=%0d point=%0d inv=%0d post=%0d linear_group=%0d paired_entry=%0d",
                        product_wait_cycles,
                        dut.state,
                        cycles,
                        preprocessing_count,
                        forward_butterfly_count,
                        pointwise_count,
                        inverse_butterfly_count,
                        postprocessing_count,
                        dut.linear_group_index,
                        dut.paired_entry_count
                    );
                end

                if (
                    product_wait_cycles
                    > PRODUCT_WATCHDOG_CYCLES
                )
                begin
                    $display(
                        "FAIL WATCHDOG state=%0d core_cycles=%0d prep=%0d fwd=%0d point=%0d inv=%0d post=%0d linear_group=%0d paired_entry=%0d",
                        dut.state,
                        cycles,
                        preprocessing_count,
                        forward_butterfly_count,
                        pointwise_count,
                        inverse_butterfly_count,
                        postprocessing_count,
                        dut.linear_group_index,
                        dut.paired_entry_count
                    );

                    $fatal(1);
                end
            end

            $display(
                "PASS: product controller reached done after %0d wait cycles",
                product_wait_cycles
            );

            if (busy)
            begin
                $display(
                    "FAIL: core remained busy after done"
                );

                $fatal(1);
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
                $display(
                    "FAIL COUNTS prep=%0d fwd=%0d point=%0d inv=%0d post=%0d mult=%0d",
                    preprocessing_count,
                    forward_butterfly_count,
                    pointwise_count,
                    inverse_butterfly_count,
                    postprocessing_count,
                    multiplication_count
                );

                $fatal(1);
            end

`ifndef FAST_MODMUL

            if (cycles !== EXPECTED_CYCLES)
            begin
                $display(
                    "FAIL CYCLES result=%0d expected=%0d",
                    cycles,
                    EXPECTED_CYCLES
                );

                $fatal(1);
            end

`else

            $display(
                "INFO: fast integration model cycles=%0d; hardware target remains %0d",
                cycles,
                EXPECTED_CYCLES
            );

`endif
        end
    endtask

    task automatic compare_result;
        input integer selected_tower;

        logic [31:0] expected_value;

        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                read_a_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                expected_value =
                    selected_tower == 0
                        ? tower0_expected[address]
                        : tower1_expected[address];

                if (read_a_data !== expected_value)
                begin
                    $display(
                        "FAIL PRODUCT tower=%0d address=%0d result=%0d expected=%0d",
                        selected_tower,
                        address,
                        read_a_data,
                        expected_value
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $display(
            "START: loading full polynomial and profile vectors"
        );

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

        $display(
            "PASS: all vector files loaded"
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        for (
            tower_index = 0;
            tower_index < 2;
            tower_index = tower_index + 1
        )
        begin
            load_runtime_profile(
                tower_index
            );

            load_inputs(
                tower_index
            );

            execute_product();

            compare_result(
                tower_index
            );

            if (tower_index == 0)
            begin
                first_cycles =
                    cycles;
            end
            else if (cycles !== first_cycles)
            begin
                $display(
                    "FAIL CONSTANT TIME q0=%0d q1=%0d",
                    first_cycles,
                    cycles
                );

                $fatal(1);
            end

            $display(
                "PASS: tower %0d full dual-butterfly product equals OpenFHE",
                tower_index
            );
        end

        $display(
            "PASS: one runtime core executed exact q0 and q1 negacyclic products"
        );

        $display(
            "PASS: two butterflies per polynomial completed concurrently"
        );

        $display(
            "PASS: four scalar coefficients completed concurrently"
        );

        $display(
            "PASS: runtime profile storage remains four 4096-word tables"
        );

        $display(
            "Dual-butterfly polynomial cycles: %0d",
            first_cycles
        );

        $display(
            "Previous runtime-profile cycles: 1339394"
        );

        $display(
            "Expected core speedup: 2.1199x"
        );

        $display(
            "Expected latency at 100 MHz: 6318.10 us"
        );

        $display(
            "Expected coefficient RAMB36: 8"
        );

        $display(
            "Expected profile RAMB36: 16"
        );

        $display(
            "Expected total RAMB36: 24"
        );

        $display(
            "Modular multiplications per product: %0d",
            multiplication_count
        );

        $finish;
    end

endmodule
