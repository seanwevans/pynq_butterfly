`timescale 1ns/1ps

module tb_poly_mul4096_dual_butterfly_two_tower_axis_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLES =
        4095;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h50524f46;

    localparam logic [31:0] COMMAND_PRODUCT =
        32'h4d554c31;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [31:0] Q1 =
        32'd1073668097;

`ifdef FAST_MODMUL

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd214018;

    localparam integer GLOBAL_WATCHDOG_CYCLES =
        800000;

`else

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd631810;

    localparam integer GLOBAL_WATCHDOG_CYCLES =
        1800000;

`endif

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic [63:0] s_axis_tdata =
        64'd0;

    logic s_axis_tvalid =
        1'b0;

    logic s_axis_tready;

    logic s_axis_tlast =
        1'b0;

    logic [63:0] m_axis_tdata;
    logic m_axis_tvalid;

    logic m_axis_tready =
        1'b0;

    logic m_axis_tlast;

    logic protocol_error;
    logic profile_ready;

    logic [31:0] active_modulus_lane0;
    logic [31:0] active_modulus_lane1;

    logic [31:0] completed_profiles;
    logic [31:0] completed_products;

    logic accelerator_busy;

    logic [31:0] core_cycles_lane0;
    logic [31:0] core_cycles_lane1;

    logic [16:0] modular_multiplications_lane0;
    logic [16:0] modular_multiplications_lane1;

    logic [31:0] profile0_twist [0:N-1];
    logic [31:0] profile1_twist [0:N-1];

    logic [31:0] profile0_forward [0:COMPACT_TWIDDLES-1];
    logic [31:0] profile1_forward [0:COMPACT_TWIDDLES-1];

    logic [31:0] profile0_inverse [0:COMPACT_TWIDDLES-1];
    logic [31:0] profile1_inverse [0:COMPACT_TWIDDLES-1];

    logic [31:0] profile0_scale [0:N-1];
    logic [31:0] profile1_scale [0:N-1];

    logic [31:0] tower0_a [0:N-1];
    logic [31:0] tower1_a [0:N-1];

    logic [31:0] tower0_b [0:N-1];
    logic [31:0] tower1_b [0:N-1];

    logic [31:0] tower0_expected [0:N-1];
    logic [31:0] tower1_expected [0:N-1];

    integer address;
    integer run_index;
    integer gap_cycles;
    integer random_seed;
    integer elapsed_cycles;

    poly_mul4096_dual_butterfly_two_tower_axis_core dut (
        .clk                           (clk),
        .reset_n                       (reset_n),

        .s_axis_tdata                  (s_axis_tdata),
        .s_axis_tvalid                 (s_axis_tvalid),
        .s_axis_tready                 (s_axis_tready),
        .s_axis_tlast                  (s_axis_tlast),

        .m_axis_tdata                  (m_axis_tdata),
        .m_axis_tvalid                 (m_axis_tvalid),
        .m_axis_tready                 (m_axis_tready),
        .m_axis_tlast                  (m_axis_tlast),

        .protocol_error                (protocol_error),
        .profile_ready                 (profile_ready),

        .active_modulus_lane0          (active_modulus_lane0),
        .active_modulus_lane1          (active_modulus_lane1),

        .completed_profiles            (completed_profiles),
        .completed_products            (completed_products),

        .accelerator_busy              (accelerator_busy),

        .core_cycles_lane0             (core_cycles_lane0),
        .core_cycles_lane1             (core_cycles_lane1),

        .modular_multiplications_lane0 (modular_multiplications_lane0),
        .modular_multiplications_lane1 (modular_multiplications_lane1)
    );

    always #5 clk = ~clk;

    task automatic send_pair(
        input logic [31:0] lane0_word,
        input logic [31:0] lane1_word,
        input logic        last
    );
        begin
            gap_cycles =
                $urandom_range(0, 3);

            repeat (gap_cycles)
            begin
                @(negedge clk);

                s_axis_tvalid =
                    1'b0;

                s_axis_tlast =
                    1'b0;
            end

            @(negedge clk);

            s_axis_tdata = {
                lane1_word,
                lane0_word
            };

            s_axis_tvalid =
                1'b1;

            s_axis_tlast =
                last;

            @(posedge clk);

            while (!s_axis_tready)
            begin
                @(posedge clk);
            end

            @(negedge clk);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;
        end
    endtask

    task automatic send_dual_profile;
        begin
            send_pair(
                COMMAND_PROFILE,
                COMMAND_PROFILE,
                1'b0
            );

            send_pair(
                Q0,
                Q1,
                1'b0
            );

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_twist[address],
                    profile1_twist[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLES;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_forward[address],
                    profile1_forward[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < COMPACT_TWIDDLES;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_inverse[address],
                    profile1_inverse[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_pair(
                    profile0_scale[address],
                    profile1_scale[address],
                    address == N - 1
                );
            end
        end
    endtask

    task automatic send_dual_product;
        begin
            send_pair(
                COMMAND_PRODUCT,
                COMMAND_PRODUCT,
                1'b0
            );

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_pair(
                    tower0_a[address],
                    tower1_a[address],
                    1'b0
                );
            end

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                send_pair(
                    tower0_b[address],
                    tower1_b[address],
                    address == N - 1
                );
            end
        end
    endtask

    task automatic receive_dual_product;
        logic [31:0] lane0_result;
        logic [31:0] lane1_result;

        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                gap_cycles =
                    $urandom_range(0, 5);

                repeat (gap_cycles)
                begin
                    @(negedge clk);

                    m_axis_tready =
                        1'b0;
                end

                @(negedge clk);

                m_axis_tready =
                    1'b1;

                @(posedge clk);

                while (!m_axis_tvalid)
                begin
                    @(posedge clk);
                end

                lane0_result =
                    m_axis_tdata[31:0];

                lane1_result =
                    m_axis_tdata[63:32];

                if (
                    lane0_result
                    !== tower0_expected[address]
                )
                begin
                    $display(
                        "FAIL TOWER0 address=%0d result=%0d expected=%0d",
                        address,
                        lane0_result,
                        tower0_expected[address]
                    );

                    $fatal(1);
                end

                if (
                    lane1_result
                    !== tower1_expected[address]
                )
                begin
                    $display(
                        "FAIL TOWER1 address=%0d result=%0d expected=%0d",
                        address,
                        lane1_result,
                        tower1_expected[address]
                    );

                    $fatal(1);
                end

                if (
                    m_axis_tlast
                    !== (address == N - 1)
                )
                begin
                    $display(
                        "FAIL TLAST address=%0d result=%0d expected=%0d",
                        address,
                        m_axis_tlast,
                        address == N - 1
                    );

                    $fatal(1);
                end

                @(negedge clk);

                m_axis_tready =
                    1'b0;
            end
        end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            elapsed_cycles <=
                0;
        end
        else
        begin
            elapsed_cycles <=
                elapsed_cycles + 1;

            if (
                elapsed_cycles != 0
                && elapsed_cycles % 100000 == 0
            )
            begin
                $display(
                    "PROGRESS AXIS elapsed=%0d profiles=%0d products=%0d busy=%0d in_ready=%0d out_valid=%0d",
                    elapsed_cycles,
                    completed_profiles,
                    completed_products,
                    accelerator_busy,
                    s_axis_tready,
                    m_axis_tvalid
                );
            end

            if (
                elapsed_cycles
                > GLOBAL_WATCHDOG_CYCLES
            )
            begin
                $display(
                    "FAIL AXIS WATCHDOG elapsed=%0d profiles=%0d products=%0d busy=%0d protocol_error=%0d lane0_cycles=%0d lane1_cycles=%0d",
                    elapsed_cycles,
                    completed_profiles,
                    completed_products,
                    accelerator_busy,
                    protocol_error,
                    core_cycles_lane0,
                    core_cycles_lane1
                );

                $fatal(1);
            end
        end
    end

    initial
    begin
        random_seed =
            32'h2f409626;

        random_seed =
            $urandom(random_seed);

        $display(
            "START: loading two-tower AXI regression vectors"
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

        $readmemh(
            "generated_dual_butterfly_axis/tower0_a.mem",
            tower0_a
        );

        $readmemh(
            "generated_dual_butterfly_axis/tower1_a.mem",
            tower1_a
        );

        $readmemh(
            "generated_dual_butterfly_axis/tower0_b.mem",
            tower0_b
        );

        $readmemh(
            "generated_dual_butterfly_axis/tower1_b.mem",
            tower1_b
        );

        $readmemh(
            "generated_dual_butterfly_axis/tower0_expected.mem",
            tower0_expected
        );

        $readmemh(
            "generated_dual_butterfly_axis/tower1_expected.mem",
            tower1_expected
        );

        $display(
            "PASS: all two-tower AXI vector files loaded"
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        $display(
            "START: streaming paired q0/q1 runtime profile"
        );

        send_dual_profile();

        while (!profile_ready)
        begin
            @(posedge clk);
        end

        if (protocol_error)
        begin
            $display(
                "FAIL: protocol error after dual profile"
            );

            $fatal(1);
        end

        if (
            active_modulus_lane0 !== Q0
            || active_modulus_lane1 !== Q1
        )
        begin
            $display(
                "FAIL MODULI lane0=%0d lane1=%0d",
                active_modulus_lane0,
                active_modulus_lane1
            );

            $fatal(1);
        end

        if (completed_profiles !== 32'd1)
        begin
            $display(
                "FAIL PROFILE COUNT result=%0d expected=1",
                completed_profiles
            );

            $fatal(1);
        end

        $display(
            "PASS: loaded q0 and q1 profiles in parallel"
        );

        for (
            run_index = 0;
            run_index < 2;
            run_index = run_index + 1
        )
        begin
            $display(
                "START: parallel two-tower AXI product run %0d",
                run_index
            );

            send_dual_product();
            receive_dual_product();

            if (protocol_error)
            begin
                $display(
                    "FAIL: protocol error after dual product"
                );

                $fatal(1);
            end

            if (
                completed_products
                !== run_index + 1
            )
            begin
                $display(
                    "FAIL PRODUCT COUNT result=%0d expected=%0d",
                    completed_products,
                    run_index + 1
                );

                $fatal(1);
            end

            if (
                core_cycles_lane0 !== EXPECTED_CYCLES
                || core_cycles_lane1 !== EXPECTED_CYCLES
            )
            begin
                $display(
                    "FAIL CYCLES lane0=%0d lane1=%0d expected=%0d",
                    core_cycles_lane0,
                    core_cycles_lane1,
                    EXPECTED_CYCLES
                );

                $fatal(1);
            end

            if (
                modular_multiplications_lane0 !== 17'd90112
                || modular_multiplications_lane1 !== 17'd90112
            )
            begin
                $display(
                    "FAIL MULTIPLICATIONS lane0=%0d lane1=%0d",
                    modular_multiplications_lane0,
                    modular_multiplications_lane1
                );

                $fatal(1);
            end

            $display(
                "PASS: parallel two-tower product run %0d",
                run_index
            );
        end

        $display(
            "PASS: both OpenFHE RNS towers completed in one core-latency interval"
        );

        $display(
            "PASS: randomized paired input gaps and output backpressure"
        );

        $display(
            "Dual profile frame words: 16384"
        );

        $display(
            "Dual profile frame bytes: 131072"
        );

        $display(
            "Dual product input frame words: 8193"
        );

        $display(
            "Dual product input frame bytes: 65544"
        );

        $display(
            "Dual product output frame words: 4096"
        );

        $display(
            "Dual product output frame bytes: 32768"
        );

        $display(
            "Parallel timing-isolated two-tower core cycles: %0d",
            core_cycles_lane0
        );

        $finish;
    end

endmodule
