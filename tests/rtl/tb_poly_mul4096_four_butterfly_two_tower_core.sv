`timescale 1ns/1ps

module tb_poly_mul4096_four_butterfly_two_tower_core;

    localparam integer N = 4096;
    localparam integer TWIDDLE_WORDS = 4095;
    localparam logic [31:0] EXPECTED_CYCLES = 32'd22968;

    localparam logic [31:0] Q0 = 32'd1073692673;
    localparam logic [30:0] MU0 = 31'h4000c001;
    localparam logic [31:0] Q1 = 32'd1073668097;
    localparam logic [30:0] MU1 = 31'h40012004;

    logic clk;
    logic reset_n;
    logic start;

    logic load_a_we;
    logic [11:0] load_a_addr;
    logic [63:0] load_a_data;

    logic load_b_we;
    logic [11:0] load_b_addr;
    logic [63:0] load_b_data;

    logic [11:0] read_a_addr;
    logic [63:0] read_a_data;

    logic [11:0] read_b_addr;
    logic [63:0] read_b_data;

    logic profile_modulus_we;
    logic [63:0] profile_modulus_data;
    logic [61:0] profile_modulus_mu_data;

    logic profile_we;
    logic [1:0] profile_bank;
    logic [11:0] profile_addr;
    logic [63:0] profile_data;

    logic profile_commit;

    logic profile_ready;
    logic [63:0] active_modulus;
    logic [61:0] active_modulus_mu;

    logic busy;
    logic done;

    logic [31:0] cycles_lane0;
    logic [31:0] cycles_lane1;

    logic [16:0] multiplication_count_lane0;
    logic [16:0] multiplication_count_lane1;

    logic [31:0] tower0_a [0:N-1];
    logic [31:0] tower0_b [0:N-1];
    logic [31:0] tower0_expected [0:N-1];

    logic [31:0] tower1_a [0:N-1];
    logic [31:0] tower1_b [0:N-1];
    logic [31:0] tower1_expected [0:N-1];

    logic [31:0] profile0_twist [0:N-1];
    logic [31:0] profile1_twist [0:N-1];

    logic [31:0] profile0_forward [0:TWIDDLE_WORDS-1];
    logic [31:0] profile1_forward [0:TWIDDLE_WORDS-1];

    logic [31:0] profile0_inverse [0:TWIDDLE_WORDS-1];
    logic [31:0] profile1_inverse [0:TWIDDLE_WORDS-1];

    logic [31:0] profile0_scale [0:N-1];
    logic [31:0] profile1_scale [0:N-1];

    integer address;
    integer wait_cycles;
    integer checked_coefficients;

    poly_mul4096_four_butterfly_two_tower_core dut (
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

        .cycles_lane0              (cycles_lane0),
        .cycles_lane1              (cycles_lane1),

        .multiplication_count_lane0(
            multiplication_count_lane0
        ),
        .multiplication_count_lane1(
            multiplication_count_lane1
        )
    );

    always #5 clk = ~clk;

    task automatic write_profile_pair (
        input logic [1:0] selected_bank,
        input logic [11:0] selected_address,
        input logic [31:0] lane0_data,
        input logic [31:0] lane1_data
    );
        begin
            profile_we = 1'b1;
            profile_bank = selected_bank;
            profile_addr = selected_address;
            profile_data = {lane1_data, lane0_data};

            @(posedge clk);
            @(negedge clk);
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

        clk = 1'b0;
        reset_n = 1'b0;
        start = 1'b0;

        load_a_we = 1'b0;
        load_a_addr = 12'd0;
        load_a_data = 64'd0;

        load_b_we = 1'b0;
        load_b_addr = 12'd0;
        load_b_data = 64'd0;

        read_a_addr = 12'd0;
        read_b_addr = 12'd0;

        profile_modulus_we = 1'b0;
        profile_modulus_data = 64'd0;
        profile_modulus_mu_data = 62'd0;

        profile_we = 1'b0;
        profile_bank = 2'd0;
        profile_addr = 12'd0;
        profile_data = 64'd0;
        profile_commit = 1'b0;

        checked_coefficients = 0;

        repeat (8) @(posedge clk);
        reset_n = 1'b1;
        @(negedge clk);

        profile_modulus_we = 1'b1;
        profile_modulus_data = {Q1, Q0};
        profile_modulus_mu_data = {MU1, MU0};

        @(posedge clk);
        @(negedge clk);

        profile_modulus_we = 1'b0;

        for (address = 0; address < N; address = address + 1)
        begin
            write_profile_pair(
                2'd0,
                address[11:0],
                profile0_twist[address],
                profile1_twist[address]
            );
        end

        for (
            address = 0;
            address < TWIDDLE_WORDS;
            address = address + 1
        )
        begin
            write_profile_pair(
                2'd1,
                address[11:0],
                profile0_forward[address],
                profile1_forward[address]
            );
        end

        for (
            address = 0;
            address < TWIDDLE_WORDS;
            address = address + 1
        )
        begin
            write_profile_pair(
                2'd2,
                address[11:0],
                profile0_inverse[address],
                profile1_inverse[address]
            );
        end

        for (address = 0; address < N; address = address + 1)
        begin
            write_profile_pair(
                2'd3,
                address[11:0],
                profile0_scale[address],
                profile1_scale[address]
            );
        end

        profile_we = 1'b0;
        profile_commit = 1'b1;

        @(posedge clk);
        @(negedge clk);

        profile_commit = 1'b0;

        if (!profile_ready)
            $fatal(1, "two-tower profile did not become ready");

        if (active_modulus !== {Q1, Q0})
            $fatal(1, "active modulus mismatch");

        if (active_modulus_mu !== {MU1, MU0})
            $fatal(1, "active reciprocal mismatch");

        $display("PASS: loaded paired q0/q1 runtime profiles");

        for (address = 0; address < N; address = address + 1)
        begin
            load_a_we = 1'b1;
            load_a_addr = address[11:0];
            load_a_data = {
                tower1_a[address],
                tower0_a[address]
            };

            load_b_we = 1'b1;
            load_b_addr = address[11:0];
            load_b_data = {
                tower1_b[address],
                tower0_b[address]
            };

            @(posedge clk);
            @(negedge clk);
        end

        load_a_we = 1'b0;
        load_b_we = 1'b0;

        $display("PASS: loaded paired q0/q1 operands");

        start = 1'b1;
        @(posedge clk);
        @(negedge clk);
        start = 1'b0;

        wait_cycles = 0;

        while (!done)
        begin
            @(posedge clk);
            @(negedge clk);
            wait_cycles = wait_cycles + 1;

            if (wait_cycles % 5000 == 0)
            begin
                $display(
                    "PROGRESS wait=%0d cycles0=%0d cycles1=%0d",
                    wait_cycles,
                    cycles_lane0,
                    cycles_lane1
                );
            end

            if (wait_cycles > 30000)
                $fatal(1, "two-tower watchdog");
        end

        if (
            cycles_lane0 !== EXPECTED_CYCLES
            || cycles_lane1 !== EXPECTED_CYCLES
        )
        begin
            $fatal(
                1,
                "cycle mismatch lane0=%0d lane1=%0d expected=%0d",
                cycles_lane0,
                cycles_lane1,
                EXPECTED_CYCLES
            );
        end

        if (
            multiplication_count_lane0 !== 17'd90112
            || multiplication_count_lane1 !== 17'd90112
        )
        begin
            $fatal(
                1,
                "multiplication count mismatch lane0=%0d lane1=%0d",
                multiplication_count_lane0,
                multiplication_count_lane1
            );
        end

        for (address = 0; address < N; address = address + 1)
        begin
            read_a_addr = address[11:0];
            @(posedge clk);
            #1;

            if (read_a_data[31:0] !== tower0_expected[address])
            begin
                $fatal(
                    1,
                    "q0 address=%0d result=%08x expected=%08x",
                    address,
                    read_a_data[31:0],
                    tower0_expected[address]
                );
            end

            if (read_a_data[63:32] !== tower1_expected[address])
            begin
                $fatal(
                    1,
                    "q1 address=%0d result=%08x expected=%08x",
                    address,
                    read_a_data[63:32],
                    tower1_expected[address]
                );
            end

            checked_coefficients = checked_coefficients + 2;
        end

        $display(
            "PASS: two towers completed exact OpenFHE product in %0d cycles",
            cycles_lane0
        );
        $display(
            "PASS: checked %0d paired coefficients",
            checked_coefficients
        );

        $finish;
    end

endmodule
