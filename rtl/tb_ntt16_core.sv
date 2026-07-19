`timescale 1ns/1ps

module tb_ntt16_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;
    logic start   = 1'b0;

    logic [31:0] q = OPENFHE_Q;

    logic        load_we   = 1'b0;
    logic [3:0]  load_addr = 4'd0;
    logic [31:0] load_data = 32'd0;

    logic [3:0]  read_addr = 4'd0;
    logic [31:0] read_data;

    logic       busy;
    logic       done;
    logic       stage_done;
    logic [1:0] stage_completed;
    logic       done_seen;

    logic [31:0] input_memory    [0:15];
    logic [31:0] expected_stage0 [0:15];
    logic [31:0] expected_stage1 [0:15];
    logic [31:0] expected_stage2 [0:15];
    logic [31:0] expected_stage3 [0:15];

    integer i;
    integer timeout_cycles;
    integer stages_seen;

    ntt16_core dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (start),

        .q               (q),

        .load_we         (load_we),
        .load_addr       (load_addr),
        .load_data       (load_data),

        .read_addr       (read_addr),
        .read_data       (read_data),

        .busy            (busy),
        .done            (done),

        .stage_done      (stage_done),
        .stage_completed (stage_completed)
    );

    always #5 clk = ~clk;

    /*
     * Latch the controller's one-clock completion pulse.
     *
     * The stage-memory checker consumes several simulation clocks,
     * so directly polling done can miss the pulse after stage 3.
     */
    always @(posedge clk)
    begin
        if (!reset_n)
            done_seen <= 1'b0;
        else if (done)
            done_seen <= 1'b1;
    end

    initial
    begin
        $readmemh(
            "../model/golden/forward_a_bit_reversed_input.mem",
            input_memory
        );

        $readmemh(
            "../model/golden/forward_a_stage0.mem",
            expected_stage0
        );

        $readmemh(
            "../model/golden/forward_a_stage1.mem",
            expected_stage1
        );

        $readmemh(
            "../model/golden/forward_a_stage2.mem",
            expected_stage2
        );

        $readmemh(
            "../model/golden/forward_a_stage3.mem",
            expected_stage3
        );
    end

    task automatic check_stage(
        input logic [1:0] stage_number
    );
        integer address;
        logic [31:0] expected;

        begin
            for (address = 0; address < 16; address = address + 1)
            begin
                read_addr = address;
                #1;

                case (stage_number)
                    2'd0:
                        expected = expected_stage0[address];

                    2'd1:
                        expected = expected_stage1[address];

                    2'd2:
                        expected = expected_stage2[address];

                    2'd3:
                        expected = expected_stage3[address];

                    default:
                        expected = 32'hxxxxxxxx;
                endcase

                if (read_data !== expected)
                begin
                    $display(
                        "FAIL stage=%0d address=%0d result=%0d expected=%0d",
                        stage_number,
                        address,
                        read_data,
                        expected
                    );

                    $fatal(1);
                end
            end

            $display(
                "PASS: stage %0d memory matches golden model",
                stage_number
            );
        end
    endtask

    initial
    begin
        /*
         * Hold reset for several complete clocks, then release it
         * away from a positive edge.
         */
        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * Load the twisted, bit-reversed input vector.
         */
        for (i = 0; i < 16; i = i + 1)
        begin
            @(negedge clk);

            load_we   = 1'b1;
            load_addr = i;
            load_data = input_memory[i];
        end

        @(negedge clk);
        load_we = 1'b0;

        /*
         * Verify the load before starting the transform.
         */
        for (i = 0; i < 16; i = i + 1)
        begin
            read_addr = i;
            #1;

            if (read_data !== input_memory[i])
            begin
                $display(
                    "FAIL load address=%0d result=%0d expected=%0d",
                    i,
                    read_data,
                    input_memory[i]
                );

                $fatal(1);
            end
        end

        $display(
            "PASS: initial NTT memory loaded"
        );

        /*
         * Start the complete four-stage transform.
         */
        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        timeout_cycles = 0;
        stages_seen    = 0;

        while (
            (done_seen !== 1'b1) &&
            (timeout_cycles < 5000)
        )
        begin
            @(negedge clk);

            timeout_cycles = timeout_cycles + 1;

            if (stage_done)
            begin
                if (stage_completed !== stages_seen)
                begin
                    $display(
                        "FAIL stage order: got=%0d expected=%0d",
                        stage_completed,
                        stages_seen
                    );

                    $fatal(1);
                end

                check_stage(stage_completed);

                stages_seen = stages_seen + 1;
            end
        end

        if (done_seen !== 1'b1)
        begin
            $display(
                "TIMEOUT after %0d controller cycles busy=%0b",
                timeout_cycles,
                busy
            );

            $fatal(1);
        end

        if (stages_seen != 4)
        begin
            $display(
                "FAIL stages_seen=%0d expected=4",
                stages_seen
            );

            $fatal(1);
        end

        if (busy !== 1'b0)
        begin
            $display(
                "FAIL busy remained asserted after completion"
            );

            $fatal(1);
        end

        $display(
            "PASS: N=16 forward cyclic NTT controller verified"
        );

        $display(
            "OpenFHE q=%0d",
            OPENFHE_Q
        );

        $display(
            "Butterflies executed: 32"
        );

        $display(
            "Observed controller cycles: %0d",
            timeout_cycles
        );

        $finish;
    end

endmodule
