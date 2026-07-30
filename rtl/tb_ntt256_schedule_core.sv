`timescale 1ns/1ps

module tb_ntt256_schedule_core;

    import ntt256_profile_pkg::*;

    localparam integer SCHEDULE_ENTRIES =
        1024;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;

    logic start   = 1'b0;
    logic advance = 1'b0;

    logic       busy;
    logic       valid;
    logic       done;

    logic [9:0] operation_index;
    logic [2:0] stage;
    logic [6:0] butterfly_index;

    logic [7:0] address_a;
    logic [7:0] address_b;
    logic [7:0] twiddle_address;

    logic [7:0] rom_address = 8'd0;

    logic [31:0] forward_twiddle;
    logic [31:0] inverse_twiddle;

    logic [31:0] expected_forward_twiddles [0:254];
    logic [31:0] expected_inverse_twiddles [0:254];

    integer csv_file;
    integer scan_count;

    reg [8*512-1:0] header_line;

    integer expected_operation;
    integer expected_stage;
    integer expected_butterfly;
    integer expected_half;
    integer expected_block;
    integer expected_local;
    integer expected_address_a;
    integer expected_address_b;
    integer expected_twiddle_address;
    integer expected_forward_twiddle;
    integer expected_inverse_twiddle;

    integer entry;
    integer address;
    integer stall_cycles;
    integer stall_index;

    integer random_seed;
    integer seed_sink;

    logic [9:0] held_operation;
    logic [2:0] held_stage;
    logic [6:0] held_butterfly;
    logic [7:0] held_address_a;
    logic [7:0] held_address_b;
    logic [7:0] held_twiddle_address;

    ntt256_schedule_core dut (
        .clk              (clk),
        .reset_n          (reset_n),

        .start            (start),
        .advance          (advance),

        .busy             (busy),
        .valid            (valid),
        .done             (done),

        .operation_index  (operation_index),
        .stage            (stage),
        .butterfly_index  (butterfly_index),

        .address_a        (address_a),
        .address_b        (address_b),
        .twiddle_address  (twiddle_address)
    );

    ntt256_twiddle_rom #(
        .INIT_FILE(
            "../tests/fixtures/ntt_n256/forward_twiddles.mem"
        )
    ) forward_rom (
        .clk     (clk),
        .address (rom_address),
        .data    (forward_twiddle)
    );

    ntt256_twiddle_rom #(
        .INIT_FILE(
            "../tests/fixtures/ntt_n256/inverse_twiddles.mem"
        )
    ) inverse_rom (
        .clk     (clk),
        .address (rom_address),
        .data    (inverse_twiddle)
    );

    always #5 clk = ~clk;

    task automatic compare_schedule;
        begin
            if (valid !== 1'b1)
            begin
                $display(
                    "FAIL: schedule invalid at expected operation %0d",
                    expected_operation
                );

                $fatal(1);
            end

            if (
                operation_index
                !== expected_operation[9:0]
            )
            begin
                $display(
                    "FAIL OPERATION result=%0d expected=%0d",
                    operation_index,
                    expected_operation
                );

                $fatal(1);
            end

            if (stage !== expected_stage[2:0])
            begin
                $display(
                    "FAIL STAGE operation=%0d result=%0d expected=%0d",
                    expected_operation,
                    stage,
                    expected_stage
                );

                $fatal(1);
            end

            if (
                butterfly_index
                !== expected_butterfly[6:0]
            )
            begin
                $display(
                    "FAIL BUTTERFLY operation=%0d result=%0d expected=%0d",
                    expected_operation,
                    butterfly_index,
                    expected_butterfly
                );

                $fatal(1);
            end

            if (
                address_a
                !== expected_address_a[7:0]
            )
            begin
                $display(
                    "FAIL ADDRESS_A operation=%0d result=%0d expected=%0d",
                    expected_operation,
                    address_a,
                    expected_address_a
                );

                $fatal(1);
            end

            if (
                address_b
                !== expected_address_b[7:0]
            )
            begin
                $display(
                    "FAIL ADDRESS_B operation=%0d result=%0d expected=%0d",
                    expected_operation,
                    address_b,
                    expected_address_b
                );

                $fatal(1);
            end

            if (
                twiddle_address
                !== expected_twiddle_address[7:0]
            )
            begin
                $display(
                    "FAIL TWIDDLE ADDRESS operation=%0d result=%0d expected=%0d",
                    expected_operation,
                    twiddle_address,
                    expected_twiddle_address
                );

                $fatal(1);
            end

            if (address_a >= address_b)
            begin
                $display(
                    "FAIL ADDRESS ORDER operation=%0d a=%0d b=%0d",
                    expected_operation,
                    address_a,
                    address_b
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_held_schedule;
        begin
            if (
                operation_index
                !== held_operation
            )
            begin
                $display(
                    "FAIL: operation changed while stalled"
                );

                $fatal(1);
            end

            if (stage !== held_stage)
            begin
                $display(
                    "FAIL: stage changed while stalled"
                );

                $fatal(1);
            end

            if (
                butterfly_index
                !== held_butterfly
            )
            begin
                $display(
                    "FAIL: butterfly changed while stalled"
                );

                $fatal(1);
            end

            if (
                address_a
                !== held_address_a
            )
            begin
                $display(
                    "FAIL: address A changed while stalled"
                );

                $fatal(1);
            end

            if (
                address_b
                !== held_address_b
            )
            begin
                $display(
                    "FAIL: address B changed while stalled"
                );

                $fatal(1);
            end

            if (
                twiddle_address
                !== held_twiddle_address
            )
            begin
                $display(
                    "FAIL: twiddle address changed while stalled"
                );

                $fatal(1);
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n256/forward_twiddles.mem",
            expected_forward_twiddles
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/inverse_twiddles.mem",
            expected_inverse_twiddles
        );

        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * Verify every word of both synchronous ROM instances.
         */
        for (
            address = 0;
            address < 255;
            address = address + 1
        )
        begin
            @(negedge clk);
            rom_address = address[7:0];

            /*
             * Allow one rising edge for the synchronous ROM read.
             */
            @(negedge clk);

            if (
                forward_twiddle
                !== expected_forward_twiddles[address]
            )
            begin
                $display(
                    "FAIL FORWARD ROM address=%0d result=%0d expected=%0d",
                    address,
                    forward_twiddle,
                    expected_forward_twiddles[address]
                );

                $fatal(1);
            end

            if (
                inverse_twiddle
                !== expected_inverse_twiddles[address]
            )
            begin
                $display(
                    "FAIL INVERSE ROM address=%0d result=%0d expected=%0d",
                    address,
                    inverse_twiddle,
                    expected_inverse_twiddles[address]
                );

                $fatal(1);
            end
        end

        $display(
            "PASS: 255 forward and inverse compact twiddle ROM words"
        );

        csv_file = $fopen(
            "../tests/fixtures/ntt_n256/butterfly_schedule.csv",
            "r"
        );

        if (csv_file == 0)
        begin
            $display(
                "FAIL: could not open butterfly_schedule.csv"
            );

            $fatal(1);
        end

        scan_count = $fgets(
            header_line,
            csv_file
        );

        if (scan_count == 0)
        begin
            $display(
                "FAIL: schedule CSV has no header"
            );

            $fatal(1);
        end

        random_seed = 32'h00c0ffee;
        seed_sink = $urandom(random_seed);

        /*
         * Launch the schedule.
         */
        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        if (
            busy !== 1'b1 ||
            valid !== 1'b1
        )
        begin
            $display(
                "FAIL: schedule did not start"
            );

            $fatal(1);
        end

        for (
            entry = 0;
            entry < SCHEDULE_ENTRIES;
            entry = entry + 1
        )
        begin
            scan_count = $fscanf(
                csv_file,
                "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
                expected_operation,
                expected_stage,
                expected_butterfly,
                expected_half,
                expected_block,
                expected_local,
                expected_address_a,
                expected_address_b,
                expected_twiddle_address,
                expected_forward_twiddle,
                expected_inverse_twiddle
            );

            if (scan_count != 11)
            begin
                $display(
                    "FAIL: CSV parse at entry=%0d fields=%0d",
                    entry,
                    scan_count
                );

                $fatal(1);
            end

            compare_schedule();

            if (
                expected_forward_twiddles[
                    twiddle_address
                ]
                !== expected_forward_twiddle
            )
            begin
                $display(
                    "FAIL FORWARD TWIDDLE operation=%0d address=%0d rom=%0d csv=%0d",
                    expected_operation,
                    twiddle_address,
                    expected_forward_twiddles[
                        twiddle_address
                    ],
                    expected_forward_twiddle
                );

                $fatal(1);
            end

            if (
                expected_inverse_twiddles[
                    twiddle_address
                ]
                !== expected_inverse_twiddle
            )
            begin
                $display(
                    "FAIL INVERSE TWIDDLE operation=%0d address=%0d rom=%0d csv=%0d",
                    expected_operation,
                    twiddle_address,
                    expected_inverse_twiddles[
                        twiddle_address
                    ],
                    expected_inverse_twiddle
                );

                $fatal(1);
            end

            held_operation =
                operation_index;

            held_stage =
                stage;

            held_butterfly =
                butterfly_index;

            held_address_a =
                address_a;

            held_address_b =
                address_b;

            held_twiddle_address =
                twiddle_address;

            /*
             * Insert zero to three random stall clocks. The current
             * schedule entry must remain unchanged throughout.
             */
            stall_cycles =
                $urandom % 4;

            for (
                stall_index = 0;
                stall_index < stall_cycles;
                stall_index = stall_index + 1
            )
            begin
                advance = 1'b0;

                @(negedge clk);

                compare_held_schedule();
            end

            /*
             * Consume the current operation.
             */
            advance = 1'b1;

            @(negedge clk);

            advance = 1'b0;

            if (entry == SCHEDULE_ENTRIES - 1)
            begin
                if (
                    done !== 1'b1 ||
                    busy !== 1'b0 ||
                    valid !== 1'b0
                )
                begin
                    $display(
                        "FAIL: final schedule completion done=%0b busy=%0b valid=%0b",
                        done,
                        busy,
                        valid
                    );

                    $fatal(1);
                end
            end
            else if (done !== 1'b0)
            begin
                $display(
                    "FAIL: early done at operation %0d",
                    expected_operation
                );

                $fatal(1);
            end
        end

        $fclose(csv_file);

        /*
         * Completion must be a one-clock pulse.
         */
        @(negedge clk);

        if (done !== 1'b0)
        begin
            $display(
                "FAIL: done remained asserted"
            );

            $fatal(1);
        end

        $display(
            "PASS: all 1024 butterfly schedule entries match golden CSV"
        );

        $display(
            "PASS: schedule remains stable under randomized stalls"
        );

        $display(
            "N=%0d stages=%0d butterflies=%0d",
            NTT_N,
            NTT_LOG_N,
            NTT_BUTTERFLIES
        );

        $display(
            "Twiddle words per direction: %0d",
            NTT_TWIDDLE_WORDS
        );

        $finish;
    end

endmodule
