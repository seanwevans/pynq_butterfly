`timescale 1ns/1ps

module tb_ntt4096_dual_butterfly_schedule_core;

    localparam integer N =
        4096;

    localparam integer PAIRS_PER_STAGE =
        1024;

    localparam integer CYCLES_PER_TRANSFORM =
        12288;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic descending =
        1'b0;

    logic busy;
    logic valid;
    logic done;

    logic [3:0] stage_bit;
    logic [9:0] pair_index;

    logic [11:0] address0_a;
    logic [11:0] address0_b;
    logic [11:0] address1_a;
    logic [11:0] address1_b;

    logic [10:0] twiddle_index0;
    logic [10:0] twiddle_index1;

    logic seen [0:N-1];

    integer address;
    integer expected_stage;
    integer stage_cycles;
    integer total_cycles;

    logic [1:0] bank0_a;
    logic [1:0] bank0_b;
    logic [1:0] bank1_a;
    logic [1:0] bank1_b;

    ntt4096_dual_butterfly_schedule_core dut (
        .clk               (clk),
        .reset_n           (reset_n),

        .start             (start),
        .descending        (descending),

        .busy              (busy),
        .valid             (valid),
        .done              (done),

        .stage_bit         (stage_bit),
        .pair_index        (pair_index),

        .address0_a        (address0_a),
        .address0_b        (address0_b),
        .address1_a        (address1_a),
        .address1_b        (address1_b),

        .twiddle_index0    (twiddle_index0),
        .twiddle_index1    (twiddle_index1)
    );

    always #5 clk = ~clk;

    function automatic [1:0] bank;
        input [11:0] coefficient_address;

        integer bit_index;

        begin
            bank =
                2'd0;

            for (
                bit_index = 0;
                bit_index < 12;
                bit_index = bit_index + 1
            )
            begin
                if ((bit_index & 1) == 0)
                begin
                    bank[0] =
                        bank[0]
                        ^ coefficient_address[bit_index];
                end
                else
                begin
                    bank[1] =
                        bank[1]
                        ^ coefficient_address[bit_index];
                end
            end
        end
    endfunction

    task automatic clear_seen;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                seen[address] =
                    1'b0;
            end
        end
    endtask

    task automatic mark_address(
        input [11:0] coefficient_address
    );
        begin
            if (seen[coefficient_address])
            begin
                $display(
                    "FAIL duplicate coefficient stage=%0d address=%0d",
                    stage_bit,
                    coefficient_address
                );

                $fatal(1);
            end

            seen[coefficient_address] =
                1'b1;
        end
    endtask

    task automatic verify_complete_stage;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                if (!seen[address])
                begin
                    $display(
                        "FAIL missing coefficient stage=%0d address=%0d",
                        stage_bit,
                        address
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    task automatic run_transform(
        input logic use_descending
    );
        begin
            clear_seen();

            expected_stage =
                use_descending
                    ? 11
                    : 0;

            stage_cycles =
                0;

            total_cycles =
                0;

            @(negedge clk);

            descending =
                use_descending;

            start =
                1'b1;

            @(negedge clk);

            start =
                1'b0;

            while (1)
            begin
                @(negedge clk);

                if (valid)
                begin
                    if (stage_bit !== expected_stage[3:0])
                    begin
                        $display(
                            "FAIL stage result=%0d expected=%0d",
                            stage_bit,
                            expected_stage
                        );

                        $fatal(1);
                    end

                    if (
                        address0_b
                        !== (
                            address0_a
                            ^ (12'd1 << stage_bit)
                        )
                    )
                    begin
                        $display(
                            "FAIL butterfly 0 relation stage=%0d",
                            stage_bit
                        );

                        $fatal(1);
                    end

                    if (
                        address1_b
                        !== (
                            address1_a
                            ^ (12'd1 << stage_bit)
                        )
                    )
                    begin
                        $display(
                            "FAIL butterfly 1 relation stage=%0d",
                            stage_bit
                        );

                        $fatal(1);
                    end

                    bank0_a =
                        bank(address0_a);

                    bank0_b =
                        bank(address0_b);

                    bank1_a =
                        bank(address1_a);

                    bank1_b =
                        bank(address1_b);

                    if (
                        bank0_a == bank0_b
                        || bank0_a == bank1_a
                        || bank0_a == bank1_b
                        || bank0_b == bank1_a
                        || bank0_b == bank1_b
                        || bank1_a == bank1_b
                    )
                    begin
                        $display(
                            "FAIL bank conflict stage=%0d pair=%0d banks=%0d,%0d,%0d,%0d",
                            stage_bit,
                            pair_index,
                            bank0_a,
                            bank0_b,
                            bank1_a,
                            bank1_b
                        );

                        $fatal(1);
                    end

                    mark_address(address0_a);
                    mark_address(address0_b);
                    mark_address(address1_a);
                    mark_address(address1_b);

                    stage_cycles =
                        stage_cycles + 1;

                    total_cycles =
                        total_cycles + 1;

                    if (stage_cycles == PAIRS_PER_STAGE)
                    begin
                        verify_complete_stage();

                        clear_seen();

                        stage_cycles =
                            0;

                        if (!done)
                        begin
                            if (use_descending)
                            begin
                                expected_stage =
                                    expected_stage - 1;
                            end
                            else
                            begin
                                expected_stage =
                                    expected_stage + 1;
                            end
                        end
                    end
                end

                if (done)
                begin
                    if (stage_cycles != 0)
                    begin
                        $display(
                            "FAIL incomplete final stage cycles=%0d",
                            stage_cycles
                        );

                        $fatal(1);
                    end

                    if (total_cycles != CYCLES_PER_TRANSFORM)
                    begin
                        $display(
                            "FAIL total cycles result=%0d expected=%0d",
                            total_cycles,
                            CYCLES_PER_TRANSFORM
                        );

                        $fatal(1);
                    end

                    if (use_descending)
                    begin
                        $display(
                            "PASS: descending DIF paired schedule covers all stages"
                        );
                    end
                    else
                    begin
                        $display(
                            "PASS: ascending DIT paired schedule covers all stages"
                        );
                    end

                    disable run_transform;
                end
            end
        end
    endtask

    initial
    begin
        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        run_transform(
            1'b1
        );

        run_transform(
            1'b0
        );

        $display(
            "PASS: four-bank parity mapping is conflict free for all 12 stage bits"
        );

        $display(
            "PASS: two butterflies are issued per schedule cycle"
        );

        $display(
            "Paired cycles per stage: 1024"
        );

        $display(
            "Paired cycles per transform: 12288"
        );

        $display(
            "Single-butterfly cycles per transform: 24576"
        );

        $display(
            "Structural butterfly issue reduction: 2.000x"
        );

        $finish;
    end

endmodule
