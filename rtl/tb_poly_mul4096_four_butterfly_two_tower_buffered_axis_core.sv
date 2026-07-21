`timescale 1ns/1ps

module tb_poly_mul4096_four_butterfly_two_tower_buffered_axis_core;

    localparam integer N = 4096;
    localparam integer TWIDDLES = 4095;
    localparam integer BATCH_SIZE = 4;
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
    logic [31:0] completed_prefetches;
    logic [31:0] completed_refills;
    logic [31:0] completed_handoffs;
    logic [31:0] last_handoff_cycles;
    logic compute_output_overlap_observed;
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

    poly_mul4096_four_butterfly_two_tower_buffered_axis_core dut (
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
        .completed_prefetches      (completed_prefetches),
        .completed_refills         (completed_refills),
        .completed_handoffs        (completed_handoffs),
        .last_handoff_cycles       (last_handoff_cycles),
        .compute_output_overlap_observed(compute_output_overlap_observed),
        .active_batch_size         (active_batch_size),
        .products_remaining        (products_remaining),
        .core_cycles_lane0         (core_cycles_lane0),
        .core_cycles_lane1         (core_cycles_lane1),
        .multiplication_count_lane0(multiplication_count_lane0),
        .multiplication_count_lane1(multiplication_count_lane1)
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

    /* Mild deterministic S2MM backpressure. */
    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            m_axis_tready <=
                1'b0;
        end
        else
        begin
            m_axis_tready <=
                runtime_cycles[4:0] != 5'd0;
        end
    end

    always @(posedge clk)
    begin
        if (!reset_n)
        begin
            received_coefficients <=
                0;

            output_complete <=
                1'b0;
        end
        else if (m_axis_tvalid && m_axis_tready)
        begin
            expected_index =
                received_coefficients % N;

            if (m_axis_tdata[31:0] !== tower0_expected[expected_index])
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

            if (m_axis_tdata[63:32] !== tower1_expected[expected_index])
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
                != (received_coefficients == TOTAL_OUTPUTS - 1)
            )
            begin
                $fatal(1, "buffered TLAST mismatch output=%0d", received_coefficients);
            end

            if (
                received_coefficients != 0
                && received_coefficients % 4096 == 0
            )
            begin
                $display(
                    "BUFFERED OUTPUT checked=%0d/%0d handoffs=%0d prefetches=%0d",
                    received_coefficients,
                    TOTAL_OUTPUTS,
                    completed_handoffs,
                    completed_prefetches
                );
            end

            if (received_coefficients == TOTAL_OUTPUTS - 1)
            begin
                output_complete <=
                    1'b1;
            end

            received_coefficients <=
                received_coefficients + 1;
        end
    end

    always @(posedge clk)
    begin
        if (!reset_n || !batch_started)
        begin
            runtime_cycles <=
                0;
        end
        else if (!output_complete)
        begin
            runtime_cycles <=
                runtime_cycles + 1;

            if (runtime_cycles != 0 && runtime_cycles % 10000 == 0)
            begin
                $display(
                    "BUFFERED RUNTIME clocks=%0d in=%0d exec=%0d out=%0d core=%0b core_cycles=%0d outputs=%0d",
                    runtime_cycles,
                    dut.input_state,
                    dut.exec_state,
                    dut.output_state,
                    dut.core_busy,
                    core_cycles_lane0,
                    received_coefficients
                );
            end

            if (runtime_cycles > 180000)
            begin
                $fatal(
                    1,
                    "buffered watchdog in=%0d exec=%0d out=%0d core=%0b outputs=%0d",
                    dut.input_state,
                    dut.exec_state,
                    dut.output_state,
                    dut.core_busy,
                    received_coefficients
                );
            end
        end
    end

    initial
    begin
        $readmemh("generated_dual_butterfly_poly/tower0_a.mem", tower0_a);
        $readmemh("generated_dual_butterfly_poly/tower0_b.mem", tower0_b);
        $readmemh("generated_dual_butterfly_poly/tower0_expected.mem", tower0_expected);
        $readmemh("generated_dual_butterfly_poly/tower1_a.mem", tower1_a);
        $readmemh("generated_dual_butterfly_poly/tower1_b.mem", tower1_b);
        $readmemh("generated_dual_butterfly_poly/tower1_expected.mem", tower1_expected);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile0/twist_factors.mem", profile0_twist);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile1/twist_factors.mem", profile1_twist);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile0/forward_twiddles.mem", profile0_forward);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile1/forward_twiddles.mem", profile1_forward);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile0/inverse_twiddles.mem", profile0_inverse);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile1/inverse_twiddles.mem", profile1_inverse);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile0/inverse_scale_factors.mem", profile0_scale);
        $readmemh("../openfhe_two_tower_runtime_bridge/vectors/profile1/inverse_scale_factors.mem", profile1_scale);

        clk = 1'b0;
        reset_n = 1'b0;
        s_axis_tdata = 64'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        batch_started = 1'b0;

        repeat (8) @(posedge clk);
        reset_n = 1'b1;

        $display("START: loading paired runtime profile");
        send_word({COMMAND_PROFILE, COMMAND_PROFILE}, 1'b0);
        send_word({Q1, Q0}, 1'b0);
        send_word({1'b0, MU1, 1'b0, MU0}, 1'b0);

        for (address = 0; address < N; address = address + 1)
            send_word({profile1_twist[address], profile0_twist[address]}, 1'b0);

        for (address = 0; address < TWIDDLES; address = address + 1)
            send_word({profile1_forward[address], profile0_forward[address]}, 1'b0);

        for (address = 0; address < TWIDDLES; address = address + 1)
            send_word({profile1_inverse[address], profile0_inverse[address]}, 1'b0);

        for (address = 0; address < N; address = address + 1)
            send_word(
                {profile1_scale[address], profile0_scale[address]},
                address == N - 1
            );

        wait (profile_ready);
        $display("PASS: paired runtime profile loaded");

        batch_started = 1'b1;
        send_word({COMMAND_BATCH, COMMAND_BATCH}, 1'b0);
        send_word({BATCH_SIZE, BATCH_SIZE}, 1'b0);

        for (
            product_index = 0;
            product_index < BATCH_SIZE;
            product_index = product_index + 1
        )
        begin
            $display("START: buffered product %0d/%0d input", product_index + 1, BATCH_SIZE);

            for (address = 0; address < N; address = address + 1)
                send_word({tower1_a[address], tower0_a[address]}, 1'b0);

            for (address = 0; address < N; address = address + 1)
                send_word(
                    {tower1_b[address], tower0_b[address]},
                    product_index == BATCH_SIZE - 1
                    && address == N - 1
                );
        end

        $display("PASS: complete buffered MM2S batch accepted");

        wait (output_complete);
        @(negedge clk);

        if (protocol_error)
            $fatal(1, "buffered AXI protocol_error asserted");

        if (
            completed_profiles != 32'd1
            || completed_products != BATCH_SIZE
            || completed_batches != 32'd1
        )
            $fatal(1, "completion counters profiles=%0d products=%0d batches=%0d", completed_profiles, completed_products, completed_batches);

        if (
            completed_prefetches != BATCH_SIZE - 1
            || completed_refills != BATCH_SIZE - 1
            || completed_handoffs != BATCH_SIZE
        )
            $fatal(1, "pipeline counters prefetch=%0d refill=%0d handoff=%0d", completed_prefetches, completed_refills, completed_handoffs);

        if (last_handoff_cycles != 32'd1025)
            $fatal(1, "handoff cycles=%0d expected=1025", last_handoff_cycles);

        if (!compute_output_overlap_observed)
            $fatal(1, "compute/output overlap was not observed");

        if (
            core_cycles_lane0 != 32'd22968
            || core_cycles_lane1 != 32'd22968
        )
            $fatal(1, "core cycles lane0=%0d lane1=%0d", core_cycles_lane0, core_cycles_lane1);

        if (received_coefficients != TOTAL_OUTPUTS)
            $fatal(1, "received outputs=%0d expected=%0d", received_coefficients, TOTAL_OUTPUTS);

        $display("PASS: %0d buffered exact two-tower OpenFHE products", BATCH_SIZE);
        $display("PASS: four-wide result/refill handoff = %0d clocks", last_handoff_cycles);
        $display("PASS: operand prefetch and compute/output overlap observed");
        $display("Steady hardware cadence: %0d cycles/product", 22968 + 1025);
        $finish;
    end

endmodule
