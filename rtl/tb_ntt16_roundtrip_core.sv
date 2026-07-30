`timescale 1ns/1ps

module tb_ntt16_roundtrip_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

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

    logic done_seen;
    logic clear_done_seen = 1'b0;

    logic [31:0] input_a [0:15];
    logic [31:0] input_b [0:15];

    integer i;

    ntt16_roundtrip_core dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (start),

        .load_we   (load_we),
        .load_addr (load_addr),
        .load_data (load_data),

        .read_addr (read_addr),
        .read_data (read_data),

        .busy      (busy),
        .done      (done)
    );

    always #5 clk = ~clk;

    /*
     * Preserve the one-clock completion pulse until the test task
     * has finished examining the output.
     */
    always @(posedge clk)
    begin
        if (!reset_n || clear_done_seen)
            done_seen <= 1'b0;
        else if (done)
            done_seen <= 1'b1;
    end

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n16/input_a.mem",
            input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n16/input_b.mem",
            input_b
        );
    end

    task automatic run_round_trip(
        input integer vector_number
    );
        integer address;
        integer timeout_cycles;
        logic [31:0] source_value;
        logic [31:0] expected_value;

        begin
            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: round-trip engine was busy before vector %0d",
                    vector_number
                );

                $fatal(1);
            end

            /*
             * Clear the completion latch from a previous run.
             */
            @(negedge clk);
            clear_done_seen = 1'b1;

            @(negedge clk);
            clear_done_seen = 1'b0;

            /*
             * Load one complete natural-order source polynomial.
             */
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                case (vector_number)
                    0:
                        source_value = input_a[address];

                    1:
                        source_value = input_b[address];

                    default:
                        source_value = 32'd0;
                endcase

                if (source_value >= OPENFHE_Q)
                begin
                    $display(
                        "INVALID INPUT vector=%0d address=%0d value=%0d",
                        vector_number,
                        address,
                        source_value
                    );

                    $fatal(1);
                end

                @(negedge clk);

                load_we   = 1'b1;
                load_addr = address;
                load_data = source_value;
            end

            @(negedge clk);
            load_we = 1'b0;

            /*
             * Start the complete forward/transfer/inverse pipeline.
             */
            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            timeout_cycles = 0;

            while (
                (done_seen !== 1'b1) &&
                (timeout_cycles < 10000)
            )
            begin
                @(negedge clk);
                timeout_cycles = timeout_cycles + 1;
            end

            if (done_seen !== 1'b1)
            begin
                $display(
                    "TIMEOUT vector=%0d cycles=%0d busy=%0b",
                    vector_number,
                    timeout_cycles,
                    busy
                );

                $fatal(1);
            end

            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: busy remained asserted for vector %0d",
                    vector_number
                );

                $fatal(1);
            end

            /*
             * Compare the recovered polynomial directly against the
             * original source polynomial.
             */
            for (
                address = 0;
                address < 16;
                address = address + 1
            )
            begin
                case (vector_number)
                    0:
                        expected_value = input_a[address];

                    1:
                        expected_value = input_b[address];

                    default:
                        expected_value = 32'd0;
                endcase

                read_addr = address;
                #1;

                if (read_data !== expected_value)
                begin
                    $display(
                        "FAIL ROUNDTRIP vector=%0d address=%0d result=%0d expected=%0d",
                        vector_number,
                        address,
                        read_data,
                        expected_value
                    );

                    $fatal(1);
                end
            end

            $display(
                "PASS: hardware round trip vector %0d recovered all 16 coefficients",
                vector_number
            );

            $display(
                "Vector %0d observed cycles: %0d",
                vector_number,
                timeout_cycles
            );
        end
    endtask

    initial
    begin
        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        run_round_trip(0);
        run_round_trip(1);

        $display(
            "PASS: forward and inverse N=16 negacyclic NTT hardware agree"
        );

        $display(
            "OpenFHE modulus: %0d",
            OPENFHE_Q
        );

        $display(
            "Successful hardware-only round trips: 2"
        );

        $finish;
    end

endmodule
