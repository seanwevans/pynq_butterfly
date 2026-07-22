`timescale 1ns/1ps

module tb_evalmul3_two_tower_axis_core;

    localparam integer N =
        64;

    localparam integer CIPHERTEXTS =
        3;

    localparam integer OUTPUT_WORDS =
        CIPHERTEXTS * N * 3;

    localparam logic [31:0] CIPHERTEXT_COUNT_WORD =
        CIPHERTEXTS;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    localparam logic [30:0] MU0 =
        31'h4000c001;

    localparam logic [30:0] MU1 =
        31'h40012004;

    localparam logic [31:0] COMMAND_PROFILE =
        32'h45565046;

    localparam logic [31:0] COMMAND_BATCH =
        32'h45564233;

    logic clk;
    logic reset_n;

    logic [63:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [63:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic        protocol_error;
    logic        profile_ready;
    logic        accelerator_busy;
    logic [63:0] active_modulus;
    logic [61:0] active_modulus_mu;
    logic [31:0] active_batch_size;
    logic [31:0] completed_profiles;
    logic [31:0] completed_ciphertexts;
    logic [31:0] completed_batches;
    logic [31:0] launched_coefficients;

    evalmul3_two_tower_axis_core #(
        .N          (N),
        .FIFO_DEPTH (8)
    ) dut (
        .clk                   (clk),
        .reset_n               (reset_n),
        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tvalid         (s_axis_tvalid),
        .s_axis_tready         (s_axis_tready),
        .s_axis_tlast          (s_axis_tlast),
        .m_axis_tdata          (m_axis_tdata),
        .m_axis_tvalid         (m_axis_tvalid),
        .m_axis_tready         (m_axis_tready),
        .m_axis_tlast          (m_axis_tlast),
        .protocol_error        (protocol_error),
        .profile_ready         (profile_ready),
        .accelerator_busy      (accelerator_busy),
        .active_modulus        (active_modulus),
        .active_modulus_mu     (active_modulus_mu),
        .active_batch_size     (active_batch_size),
        .completed_profiles    (completed_profiles),
        .completed_ciphertexts (completed_ciphertexts),
        .completed_batches     (completed_batches),
        .launched_coefficients (launched_coefficients)
    );

    always #5 clk =
        ~clk;

    logic [31:0] a0_lane0 [0:CIPHERTEXTS*N-1];
    logic [31:0] a1_lane0 [0:CIPHERTEXTS*N-1];
    logic [31:0] b0_lane0 [0:CIPHERTEXTS*N-1];
    logic [31:0] b1_lane0 [0:CIPHERTEXTS*N-1];

    logic [31:0] a0_lane1 [0:CIPHERTEXTS*N-1];
    logic [31:0] a1_lane1 [0:CIPHERTEXTS*N-1];
    logic [31:0] b0_lane1 [0:CIPHERTEXTS*N-1];
    logic [31:0] b1_lane1 [0:CIPHERTEXTS*N-1];

    logic [63:0] expected [0:OUTPUT_WORDS-1];

    function automatic logic [31:0] modmul(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] q
    );
        logic [63:0] product;
        begin
            product =
                a * b;

            modmul =
                product % q;
        end
    endfunction

    function automatic logic [31:0] addmod(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] q
    );
        logic [32:0] sum;
        begin
            sum =
                {1'b0, a}
                + {1'b0, b};

            addmod =
                sum >= {1'b0, q}
                    ? sum[31:0] - q
                    : sum[31:0];
        end
    endfunction

    task automatic send_word(
        input logic [63:0] data,
        input logic        last
    );
        begin
            @(negedge clk);

            s_axis_tdata =
                data;

            s_axis_tlast =
                last;

            s_axis_tvalid =
                1'b1;

            while (!s_axis_tready)
            begin
                @(negedge clk);
            end

            @(negedge clk);

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;

            s_axis_tdata =
                64'd0;
        end
    endtask

    integer seed;
    integer data_index;
    integer expected_index;
    integer ciphertext_index;
    integer coefficient_index;

    logic [31:0] p00_0;
    logic [31:0] p01_0;
    logic [31:0] p10_0;
    logic [31:0] p11_0;

    logic [31:0] p00_1;
    logic [31:0] p01_1;
    logic [31:0] p10_1;
    logic [31:0] p11_1;

    initial
    begin
        seed =
            32'h5eed4096;

        expected_index =
            0;

        for (
            data_index = 0;
            data_index < CIPHERTEXTS * N;
            data_index = data_index + 1
        )
        begin
            a0_lane0[data_index] =
                $urandom(seed) % Q0;

            a1_lane0[data_index] =
                $urandom(seed) % Q0;

            b0_lane0[data_index] =
                $urandom(seed) % Q0;

            b1_lane0[data_index] =
                $urandom(seed) % Q0;

            a0_lane1[data_index] =
                $urandom(seed) % Q1;

            a1_lane1[data_index] =
                $urandom(seed) % Q1;

            b0_lane1[data_index] =
                $urandom(seed) % Q1;

            b1_lane1[data_index] =
                $urandom(seed) % Q1;

            p00_0 =
                modmul(
                    a0_lane0[data_index],
                    b0_lane0[data_index],
                    Q0
                );

            p01_0 =
                modmul(
                    a0_lane0[data_index],
                    b1_lane0[data_index],
                    Q0
                );

            p10_0 =
                modmul(
                    a1_lane0[data_index],
                    b0_lane0[data_index],
                    Q0
                );

            p11_0 =
                modmul(
                    a1_lane0[data_index],
                    b1_lane0[data_index],
                    Q0
                );

            p00_1 =
                modmul(
                    a0_lane1[data_index],
                    b0_lane1[data_index],
                    Q1
                );

            p01_1 =
                modmul(
                    a0_lane1[data_index],
                    b1_lane1[data_index],
                    Q1
                );

            p10_1 =
                modmul(
                    a1_lane1[data_index],
                    b0_lane1[data_index],
                    Q1
                );

            p11_1 =
                modmul(
                    a1_lane1[data_index],
                    b1_lane1[data_index],
                    Q1
                );

            expected[expected_index] = {
                p00_1,
                p00_0
            };

            expected_index =
                expected_index + 1;

            expected[expected_index] = {
                addmod(p01_1, p10_1, Q1),
                addmod(p01_0, p10_0, Q0)
            };

            expected_index =
                expected_index + 1;

            expected[expected_index] = {
                p11_1,
                p11_0
            };

            expected_index =
                expected_index + 1;
        end
    end

    integer output_index;
    integer ready_counter;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            output_index <=
                0;

            ready_counter <=
                0;

            m_axis_tready <=
                1'b0;
        end
        else
        begin
            /*
             * Deterministic backpressure:
             * stall two clocks out of every eleven.
             */
            ready_counter <=
                ready_counter + 1;

            m_axis_tready <=
                ready_counter % 11 != 4
                && ready_counter % 11 != 5;

            if (
                m_axis_tvalid
                && m_axis_tready
            )
            begin
                if (
                    m_axis_tdata
                    !== expected[output_index]
                )
                begin
                    $display(
                        "ERROR: output %0d got=%h expected=%h",
                        output_index,
                        m_axis_tdata,
                        expected[output_index]
                    );

                    $fatal(1);
                end

                if (
                    m_axis_tlast
                    != (output_index == OUTPUT_WORDS - 1)
                )
                begin
                    $display(
                        "ERROR: TLAST mismatch at output %0d",
                        output_index
                    );

                    $fatal(1);
                end

                output_index <=
                    output_index + 1;
            end
        end
    end

    integer input_flat_index;
    logic final_input;

    initial
    begin
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

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n =
            1'b1;

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
            1'b1
        );

        if (!profile_ready)
        begin
            @(posedge clk);
        end

        send_word(
            {
                COMMAND_BATCH,
                COMMAND_BATCH
            },
            1'b0
        );

        send_word(
            {
                CIPHERTEXT_COUNT_WORD,
                CIPHERTEXT_COUNT_WORD
            },
            1'b0
        );

        for (
            ciphertext_index = 0;
            ciphertext_index < CIPHERTEXTS;
            ciphertext_index = ciphertext_index + 1
        )
        begin
            for (
                coefficient_index = 0;
                coefficient_index < N;
                coefficient_index = coefficient_index + 1
            )
            begin
                input_flat_index =
                    ciphertext_index * N
                    + coefficient_index;

                send_word(
                    {
                        a0_lane1[input_flat_index],
                        a0_lane0[input_flat_index]
                    },
                    1'b0
                );

                send_word(
                    {
                        a1_lane1[input_flat_index],
                        a1_lane0[input_flat_index]
                    },
                    1'b0
                );

                send_word(
                    {
                        b0_lane1[input_flat_index],
                        b0_lane0[input_flat_index]
                    },
                    1'b0
                );

                final_input =
                    ciphertext_index == CIPHERTEXTS - 1
                    && coefficient_index == N - 1;

                send_word(
                    {
                        b1_lane1[input_flat_index],
                        b1_lane0[input_flat_index]
                    },
                    final_input
                );
            end
        end

        fork
            begin
                wait (
                    output_index
                    == OUTPUT_WORDS
                );

                repeat (10)
                begin
                    @(posedge clk);
                end

                if (protocol_error)
                begin
                    $display(
                        "ERROR: protocol_error asserted"
                    );

                    $fatal(1);
                end

                if (
                    completed_profiles != 1
                    || completed_ciphertexts
                        != CIPHERTEXTS
                    || completed_batches != 1
                    || launched_coefficients
                        != CIPHERTEXTS * N
                )
                begin
                    $display(
                        "ERROR: completion counters profiles=%0d ciphertexts=%0d batches=%0d launched=%0d",
                        completed_profiles,
                        completed_ciphertexts,
                        completed_batches,
                        launched_coefficients
                    );

                    $fatal(1);
                end

                if (accelerator_busy)
                begin
                    $display(
                        "ERROR: accelerator remained busy after final output"
                    );

                    $fatal(1);
                end

                $display(
                    "PASS: fused two-tower evaluation-domain c0/c1/c2 exact"
                );

                $display(
                    "PASS: deterministic AXI output backpressure tolerated"
                );

                $display(
                    "PASS: %0d ciphertexts, N=%0d, %0d coefficients",
                    CIPHERTEXTS,
                    N,
                    CIPHERTEXTS * N
                );

                $finish;
            end

            begin
                repeat (200000)
                begin
                    @(posedge clk);
                end

                $display(
                    "ERROR: simulation timeout output=%0d/%0d",
                    output_index,
                    OUTPUT_WORDS
                );

                $fatal(1);
            end
        join_any
    end

endmodule
