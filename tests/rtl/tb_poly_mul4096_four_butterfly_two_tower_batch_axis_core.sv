`timescale 1ns/1ps

module tb_poly_mul4096_four_butterfly_two_tower_batch_axis_core;

    localparam integer N = 4096;
    localparam integer TWIDDLES = 4095;
    localparam integer BATCH_SIZE = 2;
    localparam integer TOTAL_OUTPUTS = BATCH_SIZE * N;

    localparam logic [31:0] COMMAND_PROFILE = 32'h50524f46;
    localparam logic [31:0] COMMAND_BATCH = 32'h4d554c42;

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
    logic [31:0] completed_batches;
    logic [31:0] active_batch_size;
    logic [31:0] products_remaining;

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
    integer product_index;
    integer received_coefficients;
    integer runtime_cycles;
    integer expected_index;

    logic batch_started;
    logic output_complete;

    poly_mul4096_four_butterfly_two_tower_batch_axis_core dut (
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
        .completed_batches         (completed_batches),
        .active_batch_size         (active_batch_size),
        .products_remaining        (products_remaining),

        .core_cycles_lane0         (core_cycles_lane0),
        .core_cycles_lane1         (core_cycles_lane1),

        .multiplication_count_lane0(
            multiplication_count_lane0
        ),

        .multiplication_count_lane1(
            multiplication_count_lane1
        )
    );

    always #5 clk = ~clk;

    task automatic send_word (
        input logic [63:0] data,
        input logic last
    );
        begin
            @(negedge clk);

            s_axis_tdata = data;
            s_axis_tvalid = 1'b1;
            s_axis_tlast = last;

            while (!s_axis_tready)
            begin
                @(negedge clk);
            end

            @(posedge clk);
            #1;

            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            received_coefficients <= 0;
            output_complete <= 1'b0;
        end
        else if (m_axis_tvalid && m_axis_tready)
        begin
            expected_index = received_coefficients % N;

            if (
                m_axis_tdata[31:0]
                !== tower0_expected[expected_index]
            )
            begin
                $fatal(
                    1,
                    "q0 output=%0d coefficient=%0d result=%08x expected=%08x",
                    received_coefficients,
                    expected_index,
                    m_axis_tdata[31:0],
                    tower0_expected[expected_index]
                );
            end

            if (
                m_axis_tdata[63:32]
                !== tower1_expected[expected_index]
            )
            begin
                $fatal(
                    1,
                    "q1 output=%0d coefficient=%0d result=%08x expected=%08x",
                    received_coefficients,
                    expected_index,
                    m_axis_tdata[63:32],
                    tower1_expected[expected_index]
                );
            end

            if (
                m_axis_tlast
                != (
                    received_coefficients
                    == TOTAL_OUTPUTS - 1
                )
            )
            begin
                $fatal(
                    1,
                    "batch TLAST mismatch output=%0d",
                    received_coefficients
                );
            end

            if (
                received_coefficients != 0
                && received_coefficients % 2048 == 0
            )
            begin
                $display(
                    "BATCH OUTPUT PROGRESS checked=%0d/%0d",
                    received_coefficients,
                    TOTAL_OUTPUTS
                );
            end

            if (received_coefficients == TOTAL_OUTPUTS - 1)
            begin
                output_complete <= 1'b1;
            end

            received_coefficients <=
                received_coefficients + 1;
        end
    end

    always @(posedge clk)
    begin
        if (!reset_n || !batch_started)
        begin
            runtime_cycles <= 0;
        end
        else if (!output_complete)
        begin
            runtime_cycles <= runtime_cycles + 1;

            if (
                runtime_cycles != 0
                && runtime_cycles % 10000 == 0
            )
            begin
                $display(
                    "BATCH RUNTIME clocks=%0d state=%0d remaining=%0d core_busy=%0b core_cycles=%0d outputs=%0d",
                    runtime_cycles,
                    dut.state,
                    products_remaining,
                    dut.core_busy,
                    core_cycles_lane0,
                    received_coefficients
                );
            end

            if (runtime_cycles > 220000)
            begin
                $fatal(
                    1,
                    "batch watchdog state=%0d remaining=%0d core_busy=%0b core_cycles=%0d outputs=%0d",
                    dut.state,
                    products_remaining,
                    dut.core_busy,
                    core_cycles_lane0,
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

        clk = 1'b0;
        reset_n = 1'b0;
        s_axis_tdata = 64'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b1;
        batch_started = 1'b0;

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n = 1'b1;

        $display(
            "START: loading paired runtime profile"
        );

        send_word(
            {COMMAND_PROFILE, COMMAND_PROFILE},
            1'b0
        );

        send_word({Q1, Q0}, 1'b0);
        send_word({1'b0, MU1, 1'b0, MU0}, 1'b0);

        for (address = 0; address < N; address = address + 1)
        begin
            send_word(
                {profile1_twist[address], profile0_twist[address]},
                1'b0
            );
        end

        for (
            address = 0;
            address < TWIDDLES;
            address = address + 1
        )
        begin
            send_word(
                {profile1_forward[address], profile0_forward[address]},
                1'b0
            );
        end

        for (
            address = 0;
            address < TWIDDLES;
            address = address + 1
        )
        begin
            send_word(
                {profile1_inverse[address], profile0_inverse[address]},
                1'b0
            );
        end

        for (address = 0; address < N; address = address + 1)
        begin
            send_word(
                {profile1_scale[address], profile0_scale[address]},
                address == N - 1
            );
        end

        wait (profile_ready);

        $display(
            "PASS: paired runtime profile loaded"
        );

        batch_started = 1'b1;

        send_word(
            {COMMAND_BATCH, COMMAND_BATCH},
            1'b0
        );

        send_word(
            {32'd2, 32'd2},
            1'b0
        );

        for (
            product_index = 0;
            product_index < BATCH_SIZE;
            product_index = product_index + 1
        )
        begin
            $display(
                "START: batch product %0d/%0d input",
                product_index + 1,
                BATCH_SIZE
            );

            for (address = 0; address < N; address = address + 1)
            begin
                send_word(
                    {tower1_a[address], tower0_a[address]},
                    1'b0
                );
            end

            for (address = 0; address < N; address = address + 1)
            begin
                send_word(
                    {tower1_b[address], tower0_b[address]},
                    product_index == BATCH_SIZE - 1
                    && address == N - 1
                );
            end
        end

        $display(
            "PASS: complete two-product MM2S batch accepted"
        );

        wait (output_complete);
        @(negedge clk);

        if (protocol_error)
        begin
            $fatal(1, "batch AXI protocol_error asserted");
        end

        if (
            completed_profiles != 32'd1
            || completed_products != BATCH_SIZE
            || completed_batches != 32'd1
        )
        begin
            $fatal(
                1,
                "completion counters profiles=%0d products=%0d batches=%0d",
                completed_profiles,
                completed_products,
                completed_batches
            );
        end

        if (
            active_batch_size != BATCH_SIZE
            || products_remaining != 32'd0
        )
        begin
            $fatal(
                1,
                "batch accounting active=%0d remaining=%0d",
                active_batch_size,
                products_remaining
            );
        end

        if (
            received_coefficients != TOTAL_OUTPUTS
        )
        begin
            $fatal(
                1,
                "received outputs=%0d expected=%0d",
                received_coefficients,
                TOTAL_OUTPUTS
            );
        end

        $display(
            "PASS: MULB produced %0d exact two-tower OpenFHE products",
            BATCH_SIZE
        );

        $display(
            "PASS: checked %0d paired output coefficients with one final TLAST",
            received_coefficients
        );

        $display(
            "Core cycles per product: %0d",
            core_cycles_lane0
        );

        $finish;
    end

endmodule
