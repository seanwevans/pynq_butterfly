`timescale 1ns/1ps

module tb_ntt4096_schedule_and_rom;

    localparam integer TWIDDLE_WORDS =
        4095;

    localparam integer BUTTERFLIES =
        24576;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic advance =
        1'b0;

    logic busy;
    logic valid;
    logic done;

    logic [14:0] operation;
    logic [3:0]  stage;
    logic [11:0] group;
    logic [11:0] j;

    logic [11:0] left_addr;
    logic [11:0] right_addr;
    logic [11:0] twiddle_addr;

    logic rom_enable =
        1'b0;

    logic [11:0] rom_address =
        12'd0;

    logic [31:0] forward_read_data;
    logic [31:0] inverse_read_data;

    logic [31:0] expected_forward_twiddle [0:TWIDDLE_WORDS-1];
    logic [31:0] expected_inverse_twiddle [0:TWIDDLE_WORDS-1];

    integer address;

    integer schedule_file;
    integer scan_count;

    reg [8*256-1:0] header_line;

    integer expected_operation;
    integer expected_stage;
    integer expected_group;
    integer expected_j;
    integer expected_left;
    integer expected_right;
    integer expected_twiddle;

    integer stall_cycles;
    integer stall_index;

    logic [14:0] held_operation;
    logic [3:0]  held_stage;
    logic [11:0] held_group;
    logic [11:0] held_j;
    logic [11:0] held_left;
    logic [11:0] held_right;
    logic [11:0] held_twiddle;

    integer random_seed;
    integer seed_sink;

    ntt4096_schedule_core scheduler (
        .clk           (clk),
        .reset_n       (reset_n),
        .start         (start),
        .advance       (advance),

        .busy          (busy),
        .valid         (valid),
        .done          (done),

        .operation     (operation),
        .stage         (stage),
        .group         (group),
        .j             (j),

        .left_addr     (left_addr),
        .right_addr    (right_addr),
        .twiddle_addr  (twiddle_addr)
    );

    ntt4096_twiddle_rom #(
        .INIT_FILE(
            "../model/golden_n4096/forward_twiddles.mem"
        )
    ) forward_rom (
        .clk       (clk),
        .enable    (rom_enable),
        .address   (rom_address),
        .read_data (forward_read_data)
    );

    ntt4096_twiddle_rom #(
        .INIT_FILE(
            "../model/golden_n4096/inverse_twiddles.mem"
        )
    ) inverse_rom (
        .clk       (clk),
        .enable    (rom_enable),
        .address   (rom_address),
        .read_data (inverse_read_data)
    );

    always #5 clk = ~clk;

    task automatic check_current_schedule;
        begin
            if (
                !busy
                || !valid
                || done
            )
            begin
                $display(
                    "FAIL SCHEDULE STATE operation=%0d busy=%0b valid=%0b done=%0b",
                    expected_operation,
                    busy,
                    valid,
                    done
                );

                $fatal(1);
            end

            if (
                operation !== expected_operation[14:0]
                || stage !== expected_stage[3:0]
                || group !== expected_group[11:0]
                || j !== expected_j[11:0]
                || left_addr !== expected_left[11:0]
                || right_addr !== expected_right[11:0]
                || twiddle_addr !== expected_twiddle[11:0]
            )
            begin
                $display(
                    "FAIL SCHEDULE operation=%0d",
                    expected_operation
                );

                $display(
                    "  actual:   stage=%0d group=%0d j=%0d left=%0d right=%0d twiddle=%0d",
                    stage,
                    group,
                    j,
                    left_addr,
                    right_addr,
                    twiddle_addr
                );

                $display(
                    "  expected: stage=%0d group=%0d j=%0d left=%0d right=%0d twiddle=%0d",
                    expected_stage,
                    expected_group,
                    expected_j,
                    expected_left,
                    expected_right,
                    expected_twiddle
                );

                $fatal(1);
            end
        end
    endtask

    task automatic capture_current_schedule;
        begin
            held_operation =
                operation;

            held_stage =
                stage;

            held_group =
                group;

            held_j =
                j;

            held_left =
                left_addr;

            held_right =
                right_addr;

            held_twiddle =
                twiddle_addr;
        end
    endtask

    task automatic require_schedule_stable;
        begin
            if (
                operation !== held_operation
                || stage !== held_stage
                || group !== held_group
                || j !== held_j
                || left_addr !== held_left
                || right_addr !== held_right
                || twiddle_addr !== held_twiddle
                || !busy
                || !valid
                || done
            )
            begin
                $display(
                    "FAIL: N=4096 schedule changed while advance was low"
                );

                $fatal(1);
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../model/golden_n4096/forward_twiddles.mem",
            expected_forward_twiddle
        );

        $readmemh(
            "../model/golden_n4096/inverse_twiddles.mem",
            expected_inverse_twiddle
        );

        random_seed =
            32'h4096c0de;

        seed_sink =
            $urandom(random_seed);

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        /*
         * Verify all forward and inverse compact twiddle words through
         * the synchronous ROM interface.
         */
        for (
            address = 0;
            address < TWIDDLE_WORDS;
            address = address + 1
        )
        begin
            @(negedge clk);

            rom_enable =
                1'b1;

            rom_address =
                address[11:0];

            @(posedge clk);
            @(negedge clk);

            if (
                forward_read_data
                !== expected_forward_twiddle[address]
            )
            begin
                $display(
                    "FAIL FORWARD TWIDDLE address=%0d result=%0d expected=%0d",
                    address,
                    forward_read_data,
                    expected_forward_twiddle[address]
                );

                $fatal(1);
            end

            if (
                inverse_read_data
                !== expected_inverse_twiddle[address]
            )
            begin
                $display(
                    "FAIL INVERSE TWIDDLE address=%0d result=%0d expected=%0d",
                    address,
                    inverse_read_data,
                    expected_inverse_twiddle[address]
                );

                $fatal(1);
            end
        end

        @(negedge clk);

        rom_enable =
            1'b0;

        $display(
            "PASS: 4095 forward and inverse compact twiddle ROM words"
        );

        schedule_file =
            $fopen(
                "../model/golden_n4096/butterfly_schedule.csv",
                "r"
            );

        if (schedule_file == 0)
        begin
            $display(
                "FAIL: could not open N=4096 butterfly_schedule.csv"
            );

            $fatal(1);
        end

        scan_count =
            $fgets(
                header_line,
                schedule_file
            );

        if (scan_count == 0)
        begin
            $display(
                "FAIL: could not read butterfly schedule header"
            );

            $fatal(1);
        end

        @(negedge clk);

        start =
            1'b1;

        @(posedge clk);
        @(negedge clk);

        start =
            1'b0;

        for (
            expected_operation = 0;
            expected_operation < BUTTERFLIES;
            expected_operation = expected_operation + 1
        )
        begin
            scan_count =
                $fscanf(
                    schedule_file,
                    "%d,%d,%d,%d,%d,%d,%d\n",
                    expected_operation,
                    expected_stage,
                    expected_group,
                    expected_j,
                    expected_left,
                    expected_right,
                    expected_twiddle
                );

            if (scan_count != 7)
            begin
                $display(
                    "FAIL: schedule CSV parse operation=%0d fields=%0d",
                    expected_operation,
                    scan_count
                );

                $fatal(1);
            end

            check_current_schedule();

            stall_cycles =
                $urandom % 6;

            for (
                stall_index = 0;
                stall_index < stall_cycles;
                stall_index = stall_index + 1
            )
            begin
                capture_current_schedule();

                @(posedge clk);
                @(negedge clk);

                require_schedule_stable();
            end

            @(negedge clk);

            advance =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            advance =
                1'b0;

            if (
                expected_operation == BUTTERFLIES - 1
            )
            begin
                if (
                    busy
                    || valid
                    || !done
                )
                begin
                    $display(
                        "FAIL FINAL STATE busy=%0b valid=%0b done=%0b",
                        busy,
                        valid,
                        done
                    );

                    $fatal(1);
                end
            end
            else
            begin
                if (
                    !busy
                    || !valid
                    || done
                )
                begin
                    $display(
                        "FAIL EARLY COMPLETION operation=%0d busy=%0b valid=%0b done=%0b",
                        expected_operation,
                        busy,
                        valid,
                        done
                    );

                    $fatal(1);
                end
            end
        end

        scan_count =
            $fscanf(
                schedule_file,
                "%d",
                expected_stage
            );

        if (scan_count != -1)
        begin
            $display(
                "FAIL: schedule CSV contains extra records"
            );

            $fatal(1);
        end

        $fclose(schedule_file);

        @(posedge clk);
        @(negedge clk);

        if (done)
        begin
            $display(
                "FAIL: schedule done pulse persisted"
            );

            $fatal(1);
        end

        $display(
            "PASS: all 24576 butterfly schedule entries match golden CSV"
        );

        $display(
            "PASS: schedule remains stable under randomized stalls"
        );

        $display(
            "N=4096 stages=12 butterflies=24576"
        );

        $display(
            "Twiddle words per direction: 4095"
        );

        $finish;
    end

endmodule
