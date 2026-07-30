`timescale 1ns/1ps

module tb_forward_ntt16_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    localparam logic [31:0] OPENFHE_PSI =
        32'd763394433;

    logic clk     = 1'b0;
    logic reset_n = 1'b0;
    logic start   = 1'b0;

    logic        load_we   = 1'b0;
    logic [3:0]  load_addr = 4'd0;
    logic [31:0] load_data = 32'd0;

    logic [3:0]  read_addr = 4'd0;
    logic [31:0] read_data;

    logic busy;
    logic done;
    logic preprocess_done;

    /*
     * Natural-order source vector.
     */
    logic [31:0] input_memory [0:15];

    /*
     * Expected state after twisting and bit-reversed placement.
     */
    logic [31:0] expected_preprocessed [0:15];

    /*
     * Expected natural-order forward negacyclic NTT.
     */
    logic [31:0] expected_output [0:15];

    logic done_seen;

    integer i;
    integer timeout_cycles;
    integer preprocess_checked;

    forward_ntt16_core dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (start),

        .load_we         (load_we),
        .load_addr       (load_addr),
        .load_data       (load_data),

        .read_addr       (read_addr),
        .read_data       (read_data),

        .busy            (busy),
        .done            (done),

        .preprocess_done (preprocess_done)
    );

    always #5 clk = ~clk;

    /*
     * Latch the one-clock completion pulse so testbench activity
     * cannot miss it.
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
            "../tests/fixtures/ntt_n16/input_a.mem",
            input_memory
        );

        $readmemh(
            "../tests/fixtures/ntt_n16/forward_a_bit_reversed_input.mem",
            expected_preprocessed
        );

        $readmemh(
            "../tests/fixtures/ntt_n16/forward_a.mem",
            expected_output
        );
    end

    task automatic check_preprocessed_memory;
        integer address;

        begin
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                read_addr = address;
                #1;

                if (
                    read_data !==
                    expected_preprocessed[address]
                )
                begin
                    $display(
                        "FAIL PREPROCESS address=%0d result=%0d expected=%0d",
                        address,
                        read_data,
                        expected_preprocessed[address]
                    );

                    $fatal(1);
                end
            end

            $display(
                "PASS: twist and bit-reversed placement match golden model"
            );
        end
    endtask

    task automatic check_final_output;
        integer address;

        begin
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                read_addr = address;
                #1;

                if (
                    read_data !==
                    expected_output[address]
                )
                begin
                    $display(
                        "FAIL OUTPUT address=%0d result=%0d expected=%0d",
                        address,
                        read_data,
                        expected_output[address]
                    );

                    $fatal(1);
                end
            end

            $display(
                "PASS: complete N=16 forward negacyclic NTT matches golden model"
            );
        end
    endtask

    initial
    begin
        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * Load ordinary natural-order coefficients.
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

        $display(
            "PASS: loaded 16 natural-order coefficients"
        );

        /*
         * Start preprocessing and the complete cyclic NTT.
         */
        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        timeout_cycles    = 0;
        preprocess_checked = 0;

        while (
            (done_seen !== 1'b1) &&
            (timeout_cycles < 5000)
        )
        begin
            @(negedge clk);

            timeout_cycles = timeout_cycles + 1;

            if (
                preprocess_done &&
                !preprocess_checked
            )
            begin
                check_preprocessed_memory();
                preprocess_checked = 1;
            end
        end

        if (done_seen !== 1'b1)
        begin
            $display(
                "TIMEOUT after %0d observed cycles busy=%0b",
                timeout_cycles,
                busy
            );

            $fatal(1);
        end

        if (!preprocess_checked)
        begin
            $display(
                "FAIL: preprocessing completion was not observed"
            );

            $fatal(1);
        end

        if (busy !== 1'b0)
        begin
            $display(
                "FAIL: busy remained asserted after completion"
            );

            $fatal(1);
        end

        check_final_output();

        $display(
            "OpenFHE q=%0d psi=%0d",
            OPENFHE_Q,
            OPENFHE_PSI
        );

        $display(
            "Twist multiplications executed: 16"
        );

        $display(
            "Cyclic NTT butterflies executed: 32"
        );

        $display(
            "Observed testbench cycles: %0d",
            timeout_cycles
        );

        $finish;
    end

endmodule
