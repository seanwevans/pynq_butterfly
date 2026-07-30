`timescale 1ns/1ps

module tb_poly_mul4096_runtime_profile_core;

    localparam integer N =
        4096;

    localparam integer COMPACT_TWIDDLE_WORDS =
        4095;

    localparam integer PROFILE_WORDS =
        16382;

    localparam logic [31:0] PROFILE_MODULUS =
        32'd1073692673;

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd1339394;

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

    logic [12:0] preprocessing_count;
    logic [14:0] forward_butterfly_count;
    logic [12:0] pointwise_count;
    logic [14:0] inverse_butterfly_count;
    logic [12:0] postprocessing_count;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];
    logic [31:0] expected_convolution [0:N-1];

    logic [31:0] twist_factors [0:N-1];
    logic [31:0] forward_twiddles [0:COMPACT_TWIDDLE_WORDS-1];
    logic [31:0] inverse_twiddles [0:COMPACT_TWIDDLE_WORDS-1];
    logic [31:0] inverse_scale_factors [0:N-1];

    logic [31:0] first_cycles;

    integer address;
    integer run_index;
    integer loaded_profile_words;

    poly_mul4096_runtime_profile_core dut (
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

    task automatic write_profile_word(
        input logic [1:0] selected_bank,
        input logic [11:0] selected_address,
        input logic [31:0] selected_data
    );
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
        begin
            loaded_profile_words =
                0;

            @(negedge clk);

            profile_modulus_we =
                1'b1;

            profile_modulus_data =
                PROFILE_MODULUS;

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
                    twist_factors[address]
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
                    forward_twiddles[address]
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
                    inverse_twiddles[address]
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
                    inverse_scale_factors[address]
                );
            end

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

            if (active_modulus !== PROFILE_MODULUS)
            begin
                $display(
                    "FAIL PROFILE MODULUS result=%0d expected=%0d",
                    active_modulus,
                    PROFILE_MODULUS
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
                "PASS: loaded modulus and %0d runtime profile words",
                loaded_profile_words
            );
        end
    endtask

    task automatic load_inputs;
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
                    input_a[address];

                load_b_we =
                    1'b1;

                load_b_addr =
                    address[11:0];

                load_b_data =
                    input_b[address];

                @(posedge clk);
            end

            @(negedge clk);

            load_a_we =
                1'b0;

            load_b_we =
                1'b0;
        end
    endtask

    task automatic run_product;
        begin
            @(negedge clk);

            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            while (!done)
            begin
                @(posedge clk);
                @(negedge clk);
            end

            if (busy)
            begin
                $display(
                    "FAIL: runtime-profile core remained busy after done"
                );

                $fatal(1);
            end

            if (
                preprocessing_count != 13'd4096
                || forward_butterfly_count != 15'd24576
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

            if (cycles !== EXPECTED_CYCLES)
            begin
                $display(
                    "FAIL CYCLES result=%0d expected=%0d",
                    cycles,
                    EXPECTED_CYCLES
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_result;
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

                if (
                    read_a_data
                    !== expected_convolution[address]
                )
                begin
                    $display(
                        "FAIL PRODUCT address=%0d result=%0d expected=%0d",
                        address,
                        read_a_data,
                        expected_convolution[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/input_a.mem",
            input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/input_b.mem",
            input_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/convolution.mem",
            expected_convolution
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/twist_factors.mem",
            twist_factors
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_twiddles.mem",
            forward_twiddles
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_twiddles.mem",
            inverse_twiddles
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_scale_factors.mem",
            inverse_scale_factors
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_runtime_profile();

        for (
            run_index = 0;
            run_index < 2;
            run_index = run_index + 1
        )
        begin
            load_inputs();
            run_product();
            compare_result();

            if (run_index == 0)
            begin
                first_cycles =
                    cycles;
            end
            else if (cycles !== first_cycles)
            begin
                $display(
                    "FAIL CONSTANT TIME first=%0d second=%0d",
                    first_cycles,
                    cycles
                );

                $fatal(1);
            end

            $display(
                "PASS: runtime-profile N=4096 product run %0d",
                run_index
            );
        end

        $display(
            "PASS: runtime-loaded q0 profile reproduces golden convolution"
        );

        $display(
            "PASS: one profile load supports repeated products"
        );

        $display(
            "PASS: runtime profile preserves constant core timing"
        );

        $display(
            "Runtime profile words: %0d",
            PROFILE_WORDS
        );

        $display(
            "Runtime profile bytes: %0d",
            PROFILE_WORDS * 4
        );

        $display(
            "Runtime modulus: %0d",
            active_modulus
        );

        $display(
            "Coefficient BRAM banks: 2"
        );

        $display(
            "Profile BRAM banks: 4"
        );

        $display(
            "Expected total RAMB36 after synthesis: 24"
        );

        $display(
            "Constant product cycles: %0d",
            first_cycles
        );

        $display(
            "Modular multiplications per product: %0d",
            multiplication_count
        );

        $finish;
    end

endmodule
