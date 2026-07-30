`timescale 1ns/1ps

module tb_ntt4096_dual_butterfly_cyclic_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLES =
        4095;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    localparam integer SINGLE_BUTTERFLY_REFERENCE_CYCLES =
        540673;

    /*
     * 270337 halved-schedule cycles plus 12288 cycles (one per
     * butterfly pair across all 12 stages) for the registered
     * butterfly inputs that isolate coefficient BRAM outputs from
     * the modular multipliers.
     */
    localparam integer EXPECTED_DUAL_BUTTERFLY_CYCLES =
        282625;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic inverse_mode =
        1'b0;

    logic modulus_we =
        1'b0;

    logic [31:0] modulus_data =
        32'd0;

    logic profile_we =
        1'b0;

    logic [11:0] profile_addr =
        12'd0;

    logic [31:0] profile_data =
        32'd0;

    logic profile_commit =
        1'b0;

    logic profile_ready;
    logic [31:0] active_modulus;

    logic load_we =
        1'b0;

    logic [11:0] load_addr =
        12'd0;

    logic [31:0] load_data =
        32'd0;

    logic inspect_valid =
        1'b0;

    logic [11:0] inspect_addr0 =
        12'd0;

    logic [11:0] inspect_addr1 =
        12'd0;

    logic [11:0] inspect_addr2 =
        12'd0;

    logic [11:0] inspect_addr3 =
        12'd0;

    logic inspect_data_valid;
    logic [31:0] inspect_data0;
    logic [31:0] inspect_data1;
    logic [31:0] inspect_data2;
    logic [31:0] inspect_data3;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [13:0] pair_count;
    logic [14:0] butterfly_count;

    logic [31:0] profile0_forward [0:COMPACT_TWIDDLES-1];
    logic [31:0] profile0_inverse [0:COMPACT_TWIDDLES-1];

    logic [31:0] profile1_forward [0:COMPACT_TWIDDLES-1];
    logic [31:0] profile1_inverse [0:COMPACT_TWIDDLES-1];

    logic [31:0] tower0_input [0:N-1];
    logic [31:0] tower0_forward_expected [0:N-1];
    logic [31:0] tower0_inverse_expected [0:N-1];

    logic [31:0] tower1_input [0:N-1];
    logic [31:0] tower1_forward_expected [0:N-1];
    logic [31:0] tower1_inverse_expected [0:N-1];

    integer address;
    integer group_index;
    integer last_cycles;
    integer q0_forward_cycles;
    integer q0_inverse_cycles;
    integer q1_forward_cycles;
    integer q1_inverse_cycles;

    ntt4096_dual_butterfly_cyclic_core dut (
        .clk                (clk),
        .reset_n            (reset_n),
        .start              (start),
        .inverse_mode       (inverse_mode),

        .modulus_we         (modulus_we),
        .modulus_data       (modulus_data),

        .profile_we         (profile_we),
        .profile_addr       (profile_addr),
        .profile_data       (profile_data),
        .profile_commit     (profile_commit),

        .profile_ready      (profile_ready),
        .active_modulus     (active_modulus),

        .load_we            (load_we),
        .load_addr          (load_addr),
        .load_data          (load_data),

        .inspect_valid      (inspect_valid),
        .inspect_addr0      (inspect_addr0),
        .inspect_addr1      (inspect_addr1),
        .inspect_addr2      (inspect_addr2),
        .inspect_addr3      (inspect_addr3),

        .inspect_data_valid (inspect_data_valid),
        .inspect_data0      (inspect_data0),
        .inspect_data1      (inspect_data1),
        .inspect_data2      (inspect_data2),
        .inspect_data3      (inspect_data3),

        .busy               (busy),
        .done               (done),

        .cycles             (cycles),
        .pair_count         (pair_count),
        .butterfly_count    (butterfly_count)
    );

    always #5 clk = ~clk;

    function automatic [31:0] select_profile_word;
        input integer tower_index;
        input integer inverse_flag;
        input integer word_index;

        begin
            if (tower_index == 0)
            begin
                if (inverse_flag != 0)
                begin
                    select_profile_word =
                        profile0_inverse[word_index];
                end
                else
                begin
                    select_profile_word =
                        profile0_forward[word_index];
                end
            end
            else
            begin
                if (inverse_flag != 0)
                begin
                    select_profile_word =
                        profile1_inverse[word_index];
                end
                else
                begin
                    select_profile_word =
                        profile1_forward[word_index];
                end
            end
        end
    endfunction

    function automatic [31:0] select_load_word;
        input integer tower_index;
        input integer use_forward_output;
        input integer word_index;

        begin
            if (tower_index == 0)
            begin
                if (use_forward_output != 0)
                begin
                    select_load_word =
                        tower0_forward_expected[word_index];
                end
                else
                begin
                    select_load_word =
                        tower0_input[word_index];
                end
            end
            else
            begin
                if (use_forward_output != 0)
                begin
                    select_load_word =
                        tower1_forward_expected[word_index];
                end
                else
                begin
                    select_load_word =
                        tower1_input[word_index];
                end
            end
        end
    endfunction

    function automatic [31:0] select_expected_word;
        input integer expected_set;
        input integer word_index;

        begin
            case (expected_set)
                0:
                    select_expected_word =
                        tower0_forward_expected[word_index];

                1:
                    select_expected_word =
                        tower0_inverse_expected[word_index];

                2:
                    select_expected_word =
                        tower1_forward_expected[word_index];

                default:
                    select_expected_word =
                        tower1_inverse_expected[word_index];
            endcase
        end
    endfunction

    task automatic load_runtime_profile;
        input integer tower_index;
        input integer inverse_flag;

        begin
            @(negedge clk);

            modulus_we =
                1'b1;

            modulus_data =
                tower_index == 0
                    ? Q0
                    : Q1;

            @(negedge clk);

            modulus_we =
                1'b0;

            for (
                address = 0;
                address < COMPACT_TWIDDLES;
                address = address + 1
            )
            begin
                profile_we =
                    1'b1;

                profile_addr =
                    address;

                profile_data =
                    select_profile_word(
                        tower_index,
                        inverse_flag,
                        address
                    );

                @(negedge clk);
            end

            profile_we =
                1'b0;

            profile_commit =
                1'b1;

            @(negedge clk);

            profile_commit =
                1'b0;

            while (!profile_ready)
            begin
                @(negedge clk);
            end

            if (
                active_modulus
                !== (
                    tower_index == 0
                        ? Q0
                        : Q1
                )
            )
            begin
                $display(
                    "FAIL ACTIVE MODULUS tower=%0d result=%0d",
                    tower_index,
                    active_modulus
                );

                $fatal(1);
            end
        end
    endtask

    task automatic load_coefficients;
        input integer tower_index;
        input integer use_forward_output;

        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                load_we =
                    1'b1;

                load_addr =
                    address;

                load_data =
                    select_load_word(
                        tower_index,
                        use_forward_output,
                        address
                    );

                @(negedge clk);
            end

            load_we =
                1'b0;
        end
    endtask

    task automatic execute_transform;
        input integer inverse_flag;

        begin
            @(negedge clk);

            inverse_mode =
                inverse_flag != 0;

            start =
                1'b1;

            @(negedge clk);

            start =
                1'b0;

            while (!done)
            begin
                @(negedge clk);
            end

            last_cycles =
                cycles;

            if (pair_count !== 14'd12288)
            begin
                $display(
                    "FAIL PAIR COUNT result=%0d expected=12288",
                    pair_count
                );

                $fatal(1);
            end

            if (butterfly_count !== 15'd24576)
            begin
                $display(
                    "FAIL BUTTERFLY COUNT result=%0d expected=24576",
                    butterfly_count
                );

                $fatal(1);
            end

            if (last_cycles != EXPECTED_DUAL_BUTTERFLY_CYCLES)
            begin
                $display(
                    "FAIL DUAL CYCLES result=%0d expected=%0d",
                    last_cycles,
                    EXPECTED_DUAL_BUTTERFLY_CYCLES
                );

                $fatal(1);
            end
        end
    endtask

    task automatic verify_coefficients;
        input integer expected_set;

        integer base_address;

        begin
            for (
                group_index = 0;
                group_index < 1024;
                group_index = group_index + 1
            )
            begin
                base_address =
                    group_index * 4;

                @(negedge clk);

                inspect_valid =
                    1'b1;

                inspect_addr0 =
                    base_address;

                inspect_addr1 =
                    base_address + 1;

                inspect_addr2 =
                    base_address + 2;

                inspect_addr3 =
                    base_address + 3;

                @(negedge clk);

                if (!inspect_data_valid)
                begin
                    $display(
                        "FAIL INSPECT VALID group=%0d",
                        group_index
                    );

                    $fatal(1);
                end

                if (
                    inspect_data0
                    !== select_expected_word(
                        expected_set,
                        base_address
                    )
                )
                begin
                    $display(
                        "FAIL COEFFICIENT address=%0d result=%0d expected=%0d",
                        base_address,
                        inspect_data0,
                        select_expected_word(expected_set, base_address)
                    );

                    $fatal(1);
                end

                if (
                    inspect_data1
                    !== select_expected_word(
                        expected_set,
                        base_address + 1
                    )
                )
                begin
                    $display(
                        "FAIL COEFFICIENT address=%0d result=%0d expected=%0d",
                        base_address + 1,
                        inspect_data1,
                        select_expected_word(expected_set, base_address + 1)
                    );

                    $fatal(1);
                end

                if (
                    inspect_data2
                    !== select_expected_word(
                        expected_set,
                        base_address + 2
                    )
                )
                begin
                    $display(
                        "FAIL COEFFICIENT address=%0d result=%0d expected=%0d",
                        base_address + 2,
                        inspect_data2,
                        select_expected_word(expected_set, base_address + 2)
                    );

                    $fatal(1);
                end

                if (
                    inspect_data3
                    !== select_expected_word(
                        expected_set,
                        base_address + 3
                    )
                )
                begin
                    $display(
                        "FAIL COEFFICIENT address=%0d result=%0d expected=%0d",
                        base_address + 3,
                        inspect_data3,
                        select_expected_word(expected_set, base_address + 3)
                    );

                    $fatal(1);
                end

                inspect_valid =
                    1'b0;
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile0/forward_twiddles.mem",
            profile0_forward
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile0/inverse_twiddles.mem",
            profile0_inverse
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile1/forward_twiddles.mem",
            profile1_forward
        );

        $readmemh(
            "../openfhe_two_tower_runtime_bridge/vectors/profile1/inverse_twiddles.mem",
            profile1_inverse
        );

        $readmemh(
            "generated_dual_butterfly/tower0_input.mem",
            tower0_input
        );

        $readmemh(
            "generated_dual_butterfly/tower0_forward_expected.mem",
            tower0_forward_expected
        );

        $readmemh(
            "generated_dual_butterfly/tower0_inverse_expected.mem",
            tower0_inverse_expected
        );

        $readmemh(
            "generated_dual_butterfly/tower1_input.mem",
            tower1_input
        );

        $readmemh(
            "generated_dual_butterfly/tower1_forward_expected.mem",
            tower1_forward_expected
        );

        $readmemh(
            "generated_dual_butterfly/tower1_inverse_expected.mem",
            tower1_inverse_expected
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_runtime_profile(0, 0);
        load_coefficients(0, 0);
        execute_transform(0);
        q0_forward_cycles = last_cycles;
        verify_coefficients(0);

        $display(
            "PASS: q0 forward DIF equals the golden bit-reversed spectrum"
        );

        load_runtime_profile(0, 1);
        load_coefficients(0, 1);
        execute_transform(1);
        q0_inverse_cycles = last_cycles;
        verify_coefficients(1);

        $display(
            "PASS: q0 inverse DIT returns N times the original coefficients"
        );

        load_runtime_profile(1, 0);
        load_coefficients(1, 0);
        execute_transform(0);
        q1_forward_cycles = last_cycles;
        verify_coefficients(2);

        $display(
            "PASS: q1 forward DIF equals the golden bit-reversed spectrum"
        );

        load_runtime_profile(1, 1);
        load_coefficients(1, 1);
        execute_transform(1);
        q1_inverse_cycles = last_cycles;
        verify_coefficients(3);

        $display(
            "PASS: q1 inverse DIT returns N times the original coefficients"
        );

        if (
            q0_forward_cycles != q0_inverse_cycles
            || q0_forward_cycles != q1_forward_cycles
            || q0_forward_cycles != q1_inverse_cycles
        )
        begin
            $display(
                "FAIL NONCONSTANT CYCLES q0f=%0d q0i=%0d q1f=%0d q1i=%0d",
                q0_forward_cycles,
                q0_inverse_cycles,
                q1_forward_cycles,
                q1_inverse_cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: one runtime core executed q0 and q1 forward and inverse transforms"
        );

        $display(
            "PASS: two butterflies completed concurrently for all 12288 pairs"
        );

        $display(
            "Dual-butterfly transform cycles: %0d",
            q0_forward_cycles
        );

        $display(
            "Single-butterfly reference cycles: %0d",
            SINGLE_BUTTERFLY_REFERENCE_CYCLES
        );

        $display(
            "Coefficient RAMB36 target: 4"
        );

        $display(
            "Twiddle RAMB36 target: 4"
        );

        $finish;
    end

endmodule
