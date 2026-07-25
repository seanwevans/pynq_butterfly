`timescale 1ns/1ps

module tb_poly_mul4096_four_butterfly_two_tower_axis_core;

    localparam integer N = 4096;
    localparam integer TWIDDLES = 4095;

    localparam logic [31:0] COMMAND_PROFILE = 32'h50524f46;
    localparam logic [31:0] COMMAND_PRODUCT = 32'h4d554c31;

    localparam logic [31:0] Q0 = 32'd1073692673;
    localparam logic [30:0] MU0 = 31'h4000c001;
    localparam logic [31:0] Q1 = 32'd1073668097;
    localparam logic [30:0] MU1 = 31'h40012004;

    logic clk;
    logic reset_n;

    logic [63:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic s_axis_tlast;

    logic [63:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic m_axis_tlast;

    logic protocol_error;
    logic profile_ready;
    logic accelerator_busy;

    logic [63:0] active_modulus;
    logic [61:0] active_modulus_mu;

    logic [31:0] completed_profiles;
    logic [31:0] completed_products;

    logic [31:0] core_cycles_lane0;
    logic [31:0] core_cycles_lane1;

    logic [16:0] multiplication_count_lane0;
    logic [16:0] multiplication_count_lane1;

    logic [31:0] tower0_a [0:N - 1];
    logic [31:0] tower0_b [0:N - 1];
    logic [31:0] tower0_expected [0:N - 1];

    logic [31:0] tower1_a [0:N - 1];
    logic [31:0] tower1_b [0:N - 1];
    logic [31:0] tower1_expected [0:N - 1];

    logic [31:0] profile0_twist [0:N - 1];
    logic [31:0] profile1_twist [0:N - 1];

    logic [31:0] profile0_forward [0:TWIDDLES - 1];
    logic [31:0] profile1_forward [0:TWIDDLES - 1];

    logic [31:0] profile0_inverse [0:TWIDDLES - 1];
    logic [31:0] profile1_inverse [0:TWIDDLES - 1];

    logic [31:0] profile0_scale [0:N - 1];
    logic [31:0] profile1_scale [0:N - 1];

    integer address;
    integer received_coefficients;
    integer product_runtime_cycles;

    logic product_started;
    logic output_complete;

    poly_mul4096_four_butterfly_two_tower_axis_core dut (
        .clk                       (clk),
        .reset_n                   (reset_n),

        .s_axis_tdata              (s_axis_tdata),
        .s_axis_tvalid             (s_axis_tvalid),
        .s_axis_tready             (s_axis_tready),
        .s_axis_tlast              (s_axis_tlast),

        .m_axis_tdata              (m_axis_tdata),
        .m_axis_tvalid             (m_axis_tvalid),
        .m_axis_tready             (m_axis_tready),
        .m_axis_tlast              (m_axis_tlast),

        .protocol_error            (protocol_error),
        .profile_ready             (profile_ready),
        .accelerator_busy          (accelerator_busy),

        .active_modulus            (active_modulus),
        .active_modulus_mu         (active_modulus_mu),

        .completed_profiles        (completed_profiles),
        .completed_products        (completed_products),

        .core_cycles_lane0         (core_cycles_lane0),
        .core_cycles_lane1         (core_cycles_lane1),

        .multiplication_count_lane0(
            multiplication_count_lane0
        ),

        .multiplication_count_lane1(
            multiplication_count_lane1
        )
    );

    always #5 clk =
        ~clk;

    /*
     * Present one AXI word before a rising edge. TREADY is sampled only
     * before the accepting edge; it may legally fall as a consequence of
     * accepting that word.
     */
    task automatic send_word (
        input logic [63:0] data,
        input logic last
    );
        begin
            @(negedge clk);

            s_axis_tdata =
                data;

            s_axis_tvalid =
                1'b1;

            s_axis_tlast =
                last;

            while (!s_axis_tready)
            begin
                @(negedge clk);
            end

            @(posedge clk);
            #1;

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;
        end
    endtask

    /*
     * Check the output independently of the input stimulus. This makes it
     * impossible for a result handshake to pass before the checker starts.
     */
    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            received_coefficients <=
                0;

            output_complete <=
                1'b0;
        end
        else if (
            m_axis_tvalid
            && m_axis_tready
        )
        begin
            if (
                received_coefficients < 0
                || received_coefficients >= N
            )
            begin
                $fatal(
                    1,
                    "unexpected extra output coefficient index=%0d",
                    received_coefficients
                );
            end

            if (
                m_axis_tdata[31:0]
                !== tower0_expected[received_coefficients]
            )
            begin
                $fatal(
                    1,
                    "q0 coefficient=%0d result=%08x expected=%08x",
                    received_coefficients,
                    m_axis_tdata[31:0],
                    tower0_expected[received_coefficients]
                );
            end

            if (
                m_axis_tdata[63:32]
                !== tower1_expected[received_coefficients]
            )
            begin
                $fatal(
                    1,
                    "q1 coefficient=%0d result=%08x expected=%08x",
                    received_coefficients,
                    m_axis_tdata[63:32],
                    tower1_expected[received_coefficients]
                );
            end

            if (
                m_axis_tlast
                != (
                    received_coefficients
                    == N - 1
                )
            )
            begin
                $fatal(
                    1,
                    "TLAST mismatch at coefficient %0d",
                    received_coefficients
                );
            end

            if (
                received_coefficients != 0
                && received_coefficients % 1024 == 0
            )
            begin
                $display(
                    "OUTPUT PROGRESS checked=%0d",
                    received_coefficients
                );
            end

            if (received_coefficients == N - 1)
            begin
                output_complete <=
                    1'b1;
            end

            received_coefficients <=
                received_coefficients + 1;
        end
    end

    /*
     * Progress and watchdog begin when the product command is sent.
     */
    always @(posedge clk)
    begin
        if (!reset_n || !product_started)
        begin
            product_runtime_cycles <=
                0;
        end
        else if (!output_complete)
        begin
            product_runtime_cycles <=
                product_runtime_cycles + 1;

            if (
                product_runtime_cycles != 0
                && product_runtime_cycles % 5000 == 0
            )
            begin
                $display(
                    "RUNTIME PROGRESS clocks=%0d state=%0d core_busy=%0b core_cycles0=%0d core_cycles1=%0d outputs=%0d",
                    product_runtime_cycles,
                    dut.state,
                    dut.core_busy,
                    core_cycles_lane0,
                    core_cycles_lane1,
                    received_coefficients
                );
            end

            if (product_runtime_cycles > 100000)
            begin
                $fatal(
                    1,
                    "runtime watchdog state=%0d core_busy=%0b core_done=%0b core_cycles0=%0d core_cycles1=%0d outputs=%0d",
                    dut.state,
                    dut.core_busy,
                    dut.core_done,
                    core_cycles_lane0,
                    core_cycles_lane1,
                    received_coefficients
                );
            end
        end
    end

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

        s_axis_tdata =
            64'd0;

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        m_axis_tready =
            1'b1;

        product_started =
            1'b0;

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n =
            1'b1;

        @(negedge clk);

        $display(
            "START: loading 16385-word paired profile frame"
        );

        send_word(
            {
                COMMAND_PROFILE,
                COMMAND_PROFILE
            },
            1'b0
        );

        send_word(
            {
                Q1,
                Q0
            },
            1'b0
        );

        send_word(
            {
                1'b0,
                MU1,
                1'b0,
                MU0
            },
            1'b0
        );

        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            send_word(
                {
                    profile1_twist[address],
                    profile0_twist[address]
                },
                1'b0
            );

            if (
                address != 0
                && address % 1024 == 0
            )
            begin
                $display(
                    "PROFILE PROGRESS twist=%0d/%0d",
                    address,
                    N
                );
            end
        end

        for (
            address = 0;
            address < TWIDDLES;
            address = address + 1
        )
        begin
            send_word(
                {
                    profile1_forward[address],
                    profile0_forward[address]
                },
                1'b0
            );

            if (
                address != 0
                && address % 1024 == 0
            )
            begin
                $display(
                    "PROFILE PROGRESS forward=%0d/%0d",
                    address,
                    TWIDDLES
                );
            end
        end

        for (
            address = 0;
            address < TWIDDLES;
            address = address + 1
        )
        begin
            send_word(
                {
                    profile1_inverse[address],
                    profile0_inverse[address]
                },
                1'b0
            );

            if (
                address != 0
                && address % 1024 == 0
            )
            begin
                $display(
                    "PROFILE PROGRESS inverse=%0d/%0d",
                    address,
                    TWIDDLES
                );
            end
        end

        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            send_word(
                {
                    profile1_scale[address],
                    profile0_scale[address]
                },
                address == N - 1
            );

            if (
                address != 0
                && address % 1024 == 0
            )
            begin
                $display(
                    "PROFILE PROGRESS scale=%0d/%0d",
                    address,
                    N
                );
            end
        end

        wait (profile_ready);

        if (
            active_modulus !== {
                Q1,
                Q0
            }
        )
        begin
            $fatal(
                1,
                "active modulus mismatch"
            );
        end

        if (
            active_modulus_mu !== {
                MU1,
                MU0
            }
        )
        begin
            $fatal(
                1,
                "active reciprocal mismatch"
            );
        end

        $display(
            "PASS: AXI profile frame loaded both towers"
        );

        $display(
            "START: sending 8193-word paired product frame"
        );

        product_started =
            1'b1;

        send_word(
            {
                COMMAND_PRODUCT,
                COMMAND_PRODUCT
            },
            1'b0
        );

        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            send_word(
                {
                    tower1_a[address],
                    tower0_a[address]
                },
                1'b0
            );

            if (
                address != 0
                && address % 1024 == 0
            )
            begin
                $display(
                    "PRODUCT PROGRESS A=%0d/%0d",
                    address,
                    N
                );
            end
        end

        for (
            address = 0;
            address < N;
            address = address + 1
        )
        begin
            send_word(
                {
                    tower1_b[address],
                    tower0_b[address]
                },
                address == N - 1
            );

            if (
                address != 0
                && address % 1024 == 0
            )
            begin
                $display(
                    "PRODUCT PROGRESS B=%0d/%0d",
                    address,
                    N
                );
            end
        end

        $display(
            "PASS: paired product frame accepted"
        );

        wait (output_complete);
        @(negedge clk);

        if (protocol_error)
        begin
            $fatal(
                1,
                "AXI protocol_error asserted"
            );
        end

        if (
            completed_profiles != 32'd1
            || completed_products != 32'd1
        )
        begin
            $fatal(
                1,
                "completion counters profile=%0d product=%0d",
                completed_profiles,
                completed_products
            );
        end

        if (
            core_cycles_lane0 != 32'd22968
            || core_cycles_lane1 != 32'd22968
        )
        begin
            $fatal(
                1,
                "core cycles lane0=%0d lane1=%0d",
                core_cycles_lane0,
                core_cycles_lane1
            );
        end

        if (received_coefficients != N)
        begin
            $fatal(
                1,
                "received coefficient count=%0d expected=%0d",
                received_coefficients,
                N
            );
        end

        $display(
            "PASS: direct 64-bit AXI frame produced exact q0/q1 OpenFHE result"
        );

        $display(
            "PASS: checked %0d paired output coefficients",
            received_coefficients
        );

        $display(
            "Core cycles per two-tower product: %0d",
            core_cycles_lane0
        );

        $finish;
    end

endmodule
