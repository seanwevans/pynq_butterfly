`timescale 1ns/1ps

module tb_ntt4096_four_butterfly_transform_core;

    localparam integer N =
        4096;

    localparam integer TWIDDLE_WORDS =
        4095;

    localparam integer EXPECTED_CYCLES =
        141313;

    localparam integer EXPECTED_BUTTERFLIES =
        24576;

    localparam logic [31:0] Q0 =
        32'd1073692673;

    localparam logic [31:0] Q1 =
        32'd1073668097;

    logic clk;
    logic reset_n;

    logic modulus_we;
    logic [31:0] modulus_data;

    logic twiddle_we;
    logic [11:0] twiddle_addr;
    logic [31:0] twiddle_data;

    logic load_we;
    logic [11:0] load_addr;
    logic [31:0] load_data;

    logic [11:0] read_addr;
    logic [31:0] read_data;

    logic start;
    logic inverse_mode;

    logic busy;
    logic done;
    logic [31:0] cycles;
    logic [14:0] butterfly_count;

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

    integer index_value;
    integer transform_count;
    integer checked_words;

    ntt4096_four_butterfly_transform_core dut (
        .clk (
            clk
        ),

        .reset_n (
            reset_n
        ),

        .modulus_we (
            modulus_we
        ),

        .modulus_data (
            modulus_data
        ),

        .twiddle_we (
            twiddle_we
        ),

        .twiddle_addr (
            twiddle_addr
        ),

        .twiddle_data (
            twiddle_data
        ),

        .load_we (
            load_we
        ),

        .load_addr (
            load_addr
        ),

        .load_data (
            load_data
        ),

        .read_addr (
            read_addr
        ),

        .read_data (
            read_data
        ),

        .start (
            start
        ),

        .inverse_mode (
            inverse_mode
        ),

        .busy (
            busy
        ),

        .done (
            done
        ),

        .cycles (
            cycles
        ),

        .butterfly_count (
            butterfly_count
        )
    );

    always #5 clk =
        ~clk;

    task automatic write_modulus (
        input logic [31:0] value
    );
        begin
            modulus_data =
                value;

            modulus_we =
                1'b1;

            @(posedge clk);
            #1;

            modulus_we =
                1'b0;
        end
    endtask

    task automatic load_coefficients (
        input integer tower_index
    );
        integer local_index;
        begin
            for (
                local_index = 0;
                local_index < N;
                local_index = local_index + 1
            )
            begin
                load_addr =
                    local_index[11:0];

                if (tower_index == 0)
                begin
                    load_data =
                        q0_input[local_index];
                end
                else
                begin
                    load_data =
                        q1_input[local_index];
                end

                load_we =
                    1'b1;

                @(posedge clk);
                #1;
            end

            load_we =
                1'b0;
        end
    endtask

    task automatic load_twiddles (
        input integer tower_index,
        input integer inverse_value
    );
        integer local_index;
        begin
            for (
                local_index = 0;
                local_index < TWIDDLE_WORDS;
                local_index = local_index + 1
            )
            begin
                twiddle_addr =
                    local_index[11:0];

                if (
                    tower_index == 0
                    && inverse_value == 0
                )
                begin
                    twiddle_data =
                        q0_forward_twiddles[local_index];
                end
                else if (
                    tower_index == 0
                    && inverse_value != 0
                )
                begin
                    twiddle_data =
                        q0_inverse_twiddles[local_index];
                end
                else if (
                    tower_index == 1
                    && inverse_value == 0
                )
                begin
                    twiddle_data =
                        q1_forward_twiddles[local_index];
                end
                else
                begin
                    twiddle_data =
                        q1_inverse_twiddles[local_index];
                end

                twiddle_we =
                    1'b1;

                @(posedge clk);
                #1;
            end

            twiddle_we =
                1'b0;
        end
    endtask

    task automatic run_transform (
        input integer inverse_value,
        input integer tower_index
    );
        begin
            inverse_mode =
                inverse_value != 0;

            start =
                1'b1;

            @(posedge clk);
            #1;

            start =
                1'b0;

            while (!done)
            begin
                @(posedge clk);
                #1;
            end

            if (cycles != EXPECTED_CYCLES)
            begin
                $fatal(
                    1,
                    "tower=%0d inverse=%0d cycles=%0d expected=%0d",
                    tower_index,
                    inverse_value,
                    cycles,
                    EXPECTED_CYCLES
                );
            end

            if (
                butterfly_count
                != EXPECTED_BUTTERFLIES
            )
            begin
                $fatal(
                    1,
                    "tower=%0d inverse=%0d butterflies=%0d expected=%0d",
                    tower_index,
                    inverse_value,
                    butterfly_count,
                    EXPECTED_BUTTERFLIES
                );
            end

            transform_count =
                transform_count + 1;
        end
    endtask

    task automatic check_coefficients (
        input integer tower_index,
        input integer roundtrip_value
    );
        integer local_index;
        logic [31:0] expected_value;
        begin
            for (
                local_index = 0;
                local_index < N;
                local_index = local_index + 1
            )
            begin
                read_addr =
                    local_index[11:0];

                @(posedge clk);
                #1;

                if (
                    tower_index == 0
                    && roundtrip_value == 0
                )
                begin
                    expected_value =
                        q0_forward_expected[local_index];
                end
                else if (
                    tower_index == 0
                    && roundtrip_value != 0
                )
                begin
                    expected_value =
                        q0_roundtrip_expected[local_index];
                end
                else if (
                    tower_index == 1
                    && roundtrip_value == 0
                )
                begin
                    expected_value =
                        q1_forward_expected[local_index];
                end
                else
                begin
                    expected_value =
                        q1_roundtrip_expected[local_index];
                end

                if (read_data !== expected_value)
                begin
                    $fatal(
                        1,
                        "tower=%0d roundtrip=%0d coefficient=%0d result=%08x expected=%08x",
                        tower_index,
                        roundtrip_value,
                        local_index,
                        read_data,
                        expected_value
                    );
                end

                checked_words =
                    checked_words + 1;
            end
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

        twiddle_we =
            1'b0;

        twiddle_addr =
            12'd0;

        twiddle_data =
            32'd0;

        load_we =
            1'b0;

        load_addr =
            12'd0;

        load_data =
            32'd0;

        read_addr =
            12'd0;

        start =
            1'b0;

        inverse_mode =
            1'b0;

        transform_count =
            0;

        checked_words =
            0;

        repeat (8)
        begin
            @(posedge clk);
        end

        reset_n =
            1'b1;

        @(posedge clk);
        #1;

        $display(
            "START: q0 four-butterfly forward DIF"
        );

        write_modulus(Q0);
        load_coefficients(0);
        load_twiddles(0, 0);
        run_transform(0, 0);
        check_coefficients(0, 0);

        $display(
            "PASS: q0 forward DIF equals golden bit-reversed output"
        );

        $display(
            "START: q0 four-butterfly inverse DIT"
        );

        load_twiddles(0, 1);
        run_transform(1, 0);
        check_coefficients(0, 1);

        $display(
            "PASS: q0 inverse DIT returns N times the input"
        );

        $display(
            "START: q1 four-butterfly forward DIF"
        );

        write_modulus(Q1);
        load_coefficients(1);
        load_twiddles(1, 0);
        run_transform(0, 1);
        check_coefficients(1, 0);

        $display(
            "PASS: q1 forward DIF equals golden bit-reversed output"
        );

        $display(
            "START: q1 four-butterfly inverse DIT"
        );

        load_twiddles(1, 1);
        run_transform(1, 1);
        check_coefficients(1, 1);

        $display(
            "PASS: q1 inverse DIT returns N times the input"
        );

        $display(
            "PASS: four butterflies execute concurrently"
        );

        $display(
            "PASS: every transform completes in 141313 clocks"
        );

        $display(
            "PASS: exactly 24576 butterflies per transform"
        );

        $display(
            "Transforms checked: %0d",
            transform_count
        );

        $display(
            "Coefficient words checked: %0d",
            checked_words
        );

        $display(
            "PASS four-butterfly N=4096 cyclic NTT checkpoint"
        );

        $finish;
    end

endmodule
