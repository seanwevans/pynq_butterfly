`timescale 1ns/1ps

module tb_ntt4096_four_butterfly_shared_ab_core;

    localparam integer N =
        4096;

    localparam integer TWIDDLE_WORDS =
        4095;

    localparam logic [31:0] EXPECTED_SEQUENCE_CYCLES =
        32'd18831;

    localparam logic [15:0] EXPECTED_FORWARD_BUTTERFLIES =
        16'd49152;

    localparam logic [14:0] EXPECTED_INVERSE_BUTTERFLIES =
        15'd24576;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [30:0] MU0 =
        31'h4000c001;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    localparam logic [30:0] MU1 =
        31'h40012004;

    logic clk;
    logic reset_n;

    logic        modulus_we;
    logic [31:0] modulus_data;
    logic [30:0] modulus_mu_data;

    logic        forward_twiddle_we;
    logic [11:0] forward_twiddle_addr;
    logic [31:0] forward_twiddle_data;

    logic        inverse_twiddle_we;
    logic [11:0] inverse_twiddle_addr;
    logic [31:0] inverse_twiddle_data;

    logic        load_a_we;
    logic [11:0] load_a_addr;
    logic [31:0] load_a_data;

    logic        load_b_we;
    logic [11:0] load_b_addr;
    logic [31:0] load_b_data;

    logic [11:0] read_a_addr;
    logic [31:0] read_a_data;

    logic [11:0] read_b_addr;
    logic [31:0] read_b_data;

    logic start;

    logic busy;
    logic done;
    logic [31:0] cycles;

    logic [1:0]  transform_count;
    logic [15:0] forward_butterfly_count;
    logic [14:0] inverse_butterfly_count;

    logic [31:0] q0_input [0:N - 1];
    logic [31:0] q0_forward_twiddles [0:TWIDDLE_WORDS - 1];
    logic [31:0] q0_inverse_twiddles [0:TWIDDLE_WORDS - 1];
    logic [31:0] q0_forward_expected [0:N - 1];
    logic [31:0] q0_roundtrip_expected [0:N - 1];

    logic [31:0] q1_input [0:N - 1];
    logic [31:0] q1_forward_twiddles [0:TWIDDLE_WORDS - 1];
    logic [31:0] q1_inverse_twiddles [0:TWIDDLE_WORDS - 1];
    logic [31:0] q1_forward_expected [0:N - 1];
    logic [31:0] q1_roundtrip_expected [0:N - 1];

    integer tower_index;
    integer address;
    integer wait_cycles;
    integer checked_coefficients;

    logic [31:0] selected_input;
    logic [31:0] selected_forward_expected;
    logic [31:0] selected_roundtrip_expected;

    ntt4096_four_butterfly_shared_ab_core dut (
        .clk                       (clk),
        .reset_n                   (reset_n),

        .modulus_we                (modulus_we),
        .modulus_data              (modulus_data),
        .modulus_mu_data           (modulus_mu_data),

        .forward_twiddle_we        (forward_twiddle_we),
        .forward_twiddle_addr      (forward_twiddle_addr),
        .forward_twiddle_data      (forward_twiddle_data),

        .inverse_twiddle_we        (inverse_twiddle_we),
        .inverse_twiddle_addr      (inverse_twiddle_addr),
        .inverse_twiddle_data      (inverse_twiddle_data),

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

        .start                     (start),

        .busy                      (busy),
        .done                      (done),
        .cycles                    (cycles),

        .transform_count           (transform_count),
        .forward_butterfly_count   (forward_butterfly_count),
        .inverse_butterfly_count   (inverse_butterfly_count)
    );

    always #5 clk =
        ~clk;

    task automatic load_tower (
        input integer selected_tower
    );
        begin
            @(negedge clk);

            modulus_we =
                1'b1;

            modulus_data =
                selected_tower == 0
                    ? Q0
                    : Q1;

            modulus_mu_data =
                selected_tower == 0
                    ? MU0
                    : MU1;

            @(posedge clk);
            @(negedge clk);

            modulus_we =
                1'b0;

            for (
                address = 0;
                address < TWIDDLE_WORDS;
                address = address + 1
            )
            begin
                forward_twiddle_addr =
                    address[11:0];

                forward_twiddle_data =
                    selected_tower == 0
                        ? q0_forward_twiddles[address]
                        : q1_forward_twiddles[address];

                inverse_twiddle_addr =
                    address[11:0];

                inverse_twiddle_data =
                    selected_tower == 0
                        ? q0_inverse_twiddles[address]
                        : q1_inverse_twiddles[address];

                forward_twiddle_we =
                    1'b1;

                inverse_twiddle_we =
                    1'b1;

                @(posedge clk);
                @(negedge clk);
            end

            forward_twiddle_we =
                1'b0;

            inverse_twiddle_we =
                1'b0;

            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                selected_input =
                    selected_tower == 0
                        ? q0_input[address]
                        : q1_input[address];

                load_a_addr =
                    address[11:0];

                load_a_data =
                    selected_input;

                load_b_addr =
                    address[11:0];

                load_b_data =
                    selected_input;

                load_a_we =
                    1'b1;

                load_b_we =
                    1'b1;

                @(posedge clk);
                @(negedge clk);
            end

            load_a_we =
                1'b0;

            load_b_we =
                1'b0;

            $display(
                "PASS: tower %0d loaded modulus, twiddles, and duplicate A/B operands",
                selected_tower
            );
        end
    endtask

    task automatic execute_sequence (
        input integer selected_tower
    );
        begin
            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            wait_cycles =
                0;

            $display(
                "START: tower %0d forward A, forward B, inverse A",
                selected_tower
            );

            while (!done)
            begin
                @(posedge clk);
                @(negedge clk);

                wait_cycles =
                    wait_cycles + 1;

                if (wait_cycles > 20000)
                begin
                    $fatal(
                        1,
                        "tower=%0d watchdog state=%0d engine_state=%0d cycles=%0d",
                        selected_tower,
                        dut.phase_state,
                        dut.engine.state,
                        cycles
                    );
                end
            end

            if (cycles !== EXPECTED_SEQUENCE_CYCLES)
            begin
                $fatal(
                    1,
                    "tower=%0d cycles=%0d expected=%0d",
                    selected_tower,
                    cycles,
                    EXPECTED_SEQUENCE_CYCLES
                );
            end

            if (transform_count !== 2'd3)
            begin
                $fatal(
                    1,
                    "tower=%0d transform_count=%0d expected=3",
                    selected_tower,
                    transform_count
                );
            end

            if (
                forward_butterfly_count
                !== EXPECTED_FORWARD_BUTTERFLIES
            )
            begin
                $fatal(
                    1,
                    "tower=%0d forward_butterflies=%0d expected=%0d",
                    selected_tower,
                    forward_butterfly_count,
                    EXPECTED_FORWARD_BUTTERFLIES
                );
            end

            if (
                inverse_butterfly_count
                !== EXPECTED_INVERSE_BUTTERFLIES
            )
            begin
                $fatal(
                    1,
                    "tower=%0d inverse_butterflies=%0d expected=%0d",
                    selected_tower,
                    inverse_butterfly_count,
                    EXPECTED_INVERSE_BUTTERFLIES
                );
            end
        end
    endtask

    task automatic check_results (
        input integer selected_tower
    );
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                read_a_addr =
                    address[11:0];

                read_b_addr =
                    address[11:0];

                @(posedge clk);
                #1;

                selected_roundtrip_expected =
                    selected_tower == 0
                        ? q0_roundtrip_expected[address]
                        : q1_roundtrip_expected[address];

                selected_forward_expected =
                    selected_tower == 0
                        ? q0_forward_expected[address]
                        : q1_forward_expected[address];

                if (read_a_data !== selected_roundtrip_expected)
                begin
                    $fatal(
                        1,
                        "tower=%0d A address=%0d result=%08x expected_roundtrip=%08x",
                        selected_tower,
                        address,
                        read_a_data,
                        selected_roundtrip_expected
                    );
                end

                if (read_b_data !== selected_forward_expected)
                begin
                    $fatal(
                        1,
                        "tower=%0d B address=%0d result=%08x expected_forward=%08x",
                        selected_tower,
                        address,
                        read_b_data,
                        selected_forward_expected
                    );
                end

                checked_coefficients =
                    checked_coefficients + 2;
            end

            $display(
                "PASS: tower %0d A roundtrip and B forward spectrum match exactly",
                selected_tower
            );
        end
    endtask

    initial
    begin
        $readmemh(
            "generated_four_butterfly_ntt/q0_input.mem",
            q0_input
        );

        $readmemh(
            "generated_four_butterfly_ntt/q0_forward_twiddles.mem",
            q0_forward_twiddles
        );

        $readmemh(
            "generated_four_butterfly_ntt/q0_inverse_twiddles.mem",
            q0_inverse_twiddles
        );

        $readmemh(
            "generated_four_butterfly_ntt/q0_forward_expected.mem",
            q0_forward_expected
        );

        $readmemh(
            "generated_four_butterfly_ntt/q0_roundtrip_expected.mem",
            q0_roundtrip_expected
        );

        $readmemh(
            "generated_four_butterfly_ntt/q1_input.mem",
            q1_input
        );

        $readmemh(
            "generated_four_butterfly_ntt/q1_forward_twiddles.mem",
            q1_forward_twiddles
        );

        $readmemh(
            "generated_four_butterfly_ntt/q1_inverse_twiddles.mem",
            q1_inverse_twiddles
        );

        $readmemh(
            "generated_four_butterfly_ntt/q1_forward_expected.mem",
            q1_forward_expected
        );

        $readmemh(
            "generated_four_butterfly_ntt/q1_roundtrip_expected.mem",
            q1_roundtrip_expected
        );

        clk =
            1'b0;

        reset_n =
            1'b0;

        modulus_we =
            1'b0;

        modulus_data =
            32'd0;

        modulus_mu_data =
            31'd0;

        forward_twiddle_we =
            1'b0;

        forward_twiddle_addr =
            12'd0;

        forward_twiddle_data =
            32'd0;

        inverse_twiddle_we =
            1'b0;

        inverse_twiddle_addr =
            12'd0;

        inverse_twiddle_data =
            32'd0;

        load_a_we =
            1'b0;

        load_a_addr =
            12'd0;

        load_a_data =
            32'd0;

        load_b_we =
            1'b0;

        load_b_addr =
            12'd0;

        load_b_data =
            32'd0;

        read_a_addr =
            12'd0;

        read_b_addr =
            12'd0;

        start =
            1'b0;

        checked_coefficients =
            0;

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n =
            1'b1;

        @(negedge clk);

        for (
            tower_index = 0;
            tower_index < 2;
            tower_index = tower_index + 1
        )
        begin
            load_tower(tower_index);
            execute_sequence(tower_index);
            check_results(tower_index);
        end

        if (checked_coefficients != 4 * N)
        begin
            $fatal(
                1,
                "checked_coefficients=%0d expected=%0d",
                checked_coefficients,
                4 * N
            );
        end

        $display(
            "PASS: shared four-lane engine completed 6 transforms and checked %0d coefficients",
            checked_coefficients
        );

        $display(
            "PASS: each tower sequence completed in %0d cycles",
            EXPECTED_SEQUENCE_CYCLES
        );

        $finish;
    end

endmodule
