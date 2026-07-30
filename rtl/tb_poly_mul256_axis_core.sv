`timescale 1ns/1ps

module tb_poly_mul256_axis_core;

    localparam integer INPUT_WORDS =
        512;

    localparam integer OUTPUT_WORDS =
        256;

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd93713;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic [31:0] s_axis_tdata =
        32'd0;

    logic [3:0] s_axis_tkeep =
        4'hf;

    logic s_axis_tvalid =
        1'b0;

    logic s_axis_tready;

    logic s_axis_tlast =
        1'b0;

    logic [31:0] m_axis_tdata;
    logic [3:0]  m_axis_tkeep;
    logic        m_axis_tvalid;

    logic m_axis_tready =
        1'b0;

    logic m_axis_tlast;

    logic busy;
    logic frame_done;
    logic protocol_error;

    logic [31:0] core_cycles;
    logic [12:0] modular_multiplication_count;

    logic [31:0] input_a [0:255];
    logic [31:0] input_b [0:255];
    logic [31:0] expected [0:255];

    logic [31:0] first_core_cycles;
    logic [31:0] second_core_cycles;

    integer input_word;
    integer output_word;

    integer gap_cycles;
    integer gap_index;

    integer timeout_cycles;

    integer random_seed;
    integer seed_sink;

    poly_mul256_axis_core #(
        .FORWARD_TWIST_INIT_FILE(
            "../tests/fixtures/ntt_n256/twist_factors.mem"
        ),

        .FORWARD_TWIDDLE_INIT_FILE(
            "../tests/fixtures/ntt_n256/forward_twiddles.mem"
        ),

        .INVERSE_TWIDDLE_INIT_FILE(
            "../tests/fixtures/ntt_n256/inverse_twiddles.mem"
        ),

        .INVERSE_SCALE_INIT_FILE(
            "../tests/fixtures/ntt_n256/inverse_scale_factors.mem"
        )
    ) dut (
        .aclk                         (clk),
        .aresetn                      (reset_n),

        .s_axis_tdata                 (s_axis_tdata),
        .s_axis_tkeep                 (s_axis_tkeep),
        .s_axis_tvalid                (s_axis_tvalid),
        .s_axis_tready                (s_axis_tready),
        .s_axis_tlast                 (s_axis_tlast),

        .m_axis_tdata                 (m_axis_tdata),
        .m_axis_tkeep                 (m_axis_tkeep),
        .m_axis_tvalid                (m_axis_tvalid),
        .m_axis_tready                (m_axis_tready),
        .m_axis_tlast                 (m_axis_tlast),

        .busy                         (busy),
        .frame_done                   (frame_done),
        .protocol_error               (protocol_error),

        .core_cycles                  (core_cycles),

        .modular_multiplication_count (
            modular_multiplication_count
        )
    );

    always #5 clk = ~clk;

    task automatic send_input_frame;
        logic [31:0] current_value;

        begin
            for (
                input_word = 0;
                input_word < INPUT_WORDS;
                input_word = input_word + 1
            )
            begin
                /*
                 * Randomized gaps model DMA throttling.
                 */
                gap_cycles =
                    $urandom % 4;

                for (
                    gap_index = 0;
                    gap_index < gap_cycles;
                    gap_index = gap_index + 1
                )
                begin
                    @(negedge clk);

                    s_axis_tvalid =
                        1'b0;

                    s_axis_tlast =
                        1'b0;
                end

                if (input_word < 256)
                begin
                    current_value =
                        input_a[input_word];
                end
                else
                begin
                    current_value =
                        input_b[input_word - 256];
                end

                @(negedge clk);

                s_axis_tdata =
                    current_value;

                s_axis_tkeep =
                    4'hf;

                s_axis_tlast =
                    input_word == INPUT_WORDS - 1;

                s_axis_tvalid =
                    1'b1;

                while (!s_axis_tready)
                    @(posedge clk);

                /*
                 * The transfer is accepted on this rising edge.
                 */
                @(posedge clk);

                @(negedge clk);

                s_axis_tvalid =
                    1'b0;

                s_axis_tlast =
                    1'b0;
            end

            $display(
                "PASS: streamed 512-word A||B input packet"
            );
        end
    endtask

    task automatic receive_output_frame(
        input integer frame_number
    );
        logic [31:0] held_data;
        logic        held_last;

        begin
            output_word =
                0;

            timeout_cycles =
                0;

            while (
                (output_word < OUTPUT_WORDS) &&
                (timeout_cycles < 300000)
            )
            begin
                /*
                 * Randomized receive backpressure.
                 */
                @(negedge clk);

                m_axis_tready =
                    ($urandom % 4) != 0;

                /*
                 * Confirm the master holds its payload stable whenever
                 * TVALID is asserted without a handshake.
                 */
                if (
                    m_axis_tvalid &&
                    !m_axis_tready
                )
                begin
                    held_data =
                        m_axis_tdata;

                    held_last =
                        m_axis_tlast;

                    @(posedge clk);
                    @(negedge clk);

                    if (m_axis_tvalid)
                    begin
                        if (
                            m_axis_tdata !== held_data ||
                            m_axis_tlast !== held_last
                        )
                        begin
                            $display(
                                "FAIL: AXI output changed under backpressure"
                            );

                            $fatal(1);
                        end
                    end
                end
                else
                begin
                    @(posedge clk);

                    if (
                        m_axis_tvalid &&
                        m_axis_tready
                    )
                    begin
                        if (m_axis_tkeep !== 4'hf)
                        begin
                            $display(
                                "FAIL TKEEP output=%0d value=%0b",
                                output_word,
                                m_axis_tkeep
                            );

                            $fatal(1);
                        end

                        if (
                            m_axis_tdata
                            !== expected[output_word]
                        )
                        begin
                            $display(
                                "FAIL STREAM RESULT frame=%0d address=%0d result=%0d expected=%0d",
                                frame_number,
                                output_word,
                                m_axis_tdata,
                                expected[output_word]
                            );

                            $fatal(1);
                        end

                        if (
                            (output_word == OUTPUT_WORDS - 1) &&
                            !m_axis_tlast
                        )
                        begin
                            $display(
                                "FAIL: final output word lacks TLAST"
                            );

                            $fatal(1);
                        end

                        if (
                            (output_word != OUTPUT_WORDS - 1) &&
                            m_axis_tlast
                        )
                        begin
                            $display(
                                "FAIL: early output TLAST at word %0d",
                                output_word
                            );

                            $fatal(1);
                        end

                        output_word =
                            output_word + 1;
                    end
                end

                timeout_cycles =
                    timeout_cycles + 1;
            end

            m_axis_tready =
                1'b0;

            if (output_word != OUTPUT_WORDS)
            begin
                $display(
                    "TIMEOUT frame=%0d output_words=%0d busy=%0b",
                    frame_number,
                    output_word,
                    busy
                );

                $fatal(1);
            end

            $display(
                "PASS: received 256-word result packet %0d with correct TLAST",
                frame_number
            );
        end
    endtask

    task automatic run_frame(
        input integer frame_number
    );
        begin
            if (
                busy !== 1'b0 ||
                s_axis_tready !== 1'b1
            )
            begin
                $display(
                    "FAIL: stream engine not ready before frame %0d",
                    frame_number
                );

                $fatal(1);
            end

            send_input_frame();
            receive_output_frame(frame_number);

            /*
             * Allow the final output handshake to return the adapter
             * to its receive state.
             */
            repeat (2) @(posedge clk);

            if (protocol_error)
            begin
                $display(
                    "FAIL: protocol error after valid frame %0d",
                    frame_number
                );

                $fatal(1);
            end

            if (
                core_cycles !== EXPECTED_CYCLES
            )
            begin
                $display(
                    "FAIL CORE CYCLES frame=%0d result=%0d expected=%0d",
                    frame_number,
                    core_cycles,
                    EXPECTED_CYCLES
                );

                $fatal(1);
            end

            if (
                modular_multiplication_count
                !== 13'd4096
            )
            begin
                $display(
                    "FAIL MULTIPLICATION COUNT frame=%0d result=%0d expected=4096",
                    frame_number,
                    modular_multiplication_count
                );

                $fatal(1);
            end

            if (frame_number == 0)
            begin
                first_core_cycles =
                    core_cycles;
            end
            else
            begin
                second_core_cycles =
                    core_cycles;
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n256/input_a.mem",
            input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/input_b.mem",
            input_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/convolution.mem",
            expected
        );

        random_seed =
            32'h00c0ffee;

        seed_sink =
            $urandom(random_seed);

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        repeat (2) @(posedge clk);

        run_frame(0);
        run_frame(1);

        if (
            first_core_cycles
            !== second_core_cycles
        )
        begin
            $display(
                "FAIL: core timing changed first=%0d second=%0d",
                first_core_cycles,
                second_core_cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: two back-to-back AXI4-Stream polynomial products"
        );

        $display(
            "PASS: randomized input gaps and output backpressure"
        );

        $display(
            "PASS: all 256 coefficients match golden convolution"
        );

        $display(
            "Input frame bytes: 2048"
        );

        $display(
            "Output frame bytes: 1024"
        );

        $display(
            "Constant core cycles: %0d",
            first_core_cycles
        );

        $display(
            "Modular multiplications per product: 4096"
        );

        $finish;
    end

endmodule
