`timescale 1ns/1ps

module tb_ntt256_cyclic_core;

    import ntt256_profile_pkg::*;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic start = 1'b0;

    logic load_we = 1'b0;
    logic [7:0] load_addr = 8'd0;
    logic [31:0] load_data = 32'd0;

    logic [7:0] read_addr = 8'd0;
    logic [31:0] read_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [10:0] butterfly_count;

    logic done_seen = 1'b0;
    logic clear_done_seen = 1'b0;

    logic [31:0] input_a [0:255];
    logic [31:0] input_b [0:255];

    logic [31:0] expected_a [0:255];
    logic [31:0] expected_b [0:255];

    integer address;
    integer timeout_cycles;

    logic [31:0] first_cycle_count;
    logic [31:0] second_cycle_count;

    ntt256_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            "../model/golden_n256/forward_twiddles.mem"
        )
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .start            (start),

        .load_we          (load_we),
        .load_addr        (load_addr),
        .load_data        (load_data),

        .read_addr        (read_addr),
        .read_data        (read_data),

        .busy             (busy),
        .done             (done),

        .cycles           (cycles),
        .butterfly_count  (butterfly_count)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
    begin
        if (!reset_n || clear_done_seen)
        begin
            done_seen <= 1'b0;
        end
        else if (done)
        begin
            done_seen <= 1'b1;
        end
    end

    task automatic clear_completion;
        begin
            @(negedge clk);
            clear_done_seen = 1'b1;

            @(negedge clk);
            clear_done_seen = 1'b0;
        end
    endtask

    task automatic load_vector(
        input integer vector_number
    );
        begin
            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: attempted load while busy"
                );

                $fatal(1);
            end

            for (
                address = 0;
                address < NTT_N;
                address = address + 1
            )
            begin
                @(negedge clk);

                load_we =
                    1'b1;

                load_addr =
                    address[7:0];

                if (vector_number == 0)
                begin
                    load_data =
                        input_a[address];
                end
                else
                begin
                    load_data =
                        input_b[address];
                end
            end

            @(negedge clk);

            load_we =
                1'b0;

            $display(
                "PASS: loaded N=256 bit-reversed vector %0d",
                vector_number
            );
        end
    endtask

    task automatic compare_result(
        input integer vector_number
    );
        logic [31:0] expected_value;

        begin
            for (
                address = 0;
                address < NTT_N;
                address = address + 1
            )
            begin
                @(negedge clk);

                read_addr =
                    address[7:0];

                /*
                 * External coefficient-memory reads are synchronous.
                 */
                @(negedge clk);

                if (vector_number == 0)
                begin
                    expected_value =
                        expected_a[address];
                end
                else
                begin
                    expected_value =
                        expected_b[address];
                end

                if (read_data !== expected_value)
                begin
                    $display(
                        "FAIL NTT vector=%0d address=%0d result=%0d expected=%0d",
                        vector_number,
                        address,
                        read_data,
                        expected_value
                    );

                    $fatal(1);
                end
            end

            $display(
                "PASS: N=256 cyclic NTT vector %0d matches golden model",
                vector_number
            );
        end
    endtask

    task automatic run_vector(
        input integer vector_number
    );
        begin
            clear_completion();
            load_vector(vector_number);

            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            timeout_cycles = 0;

            while (
                (done_seen !== 1'b1) &&
                (timeout_cycles < 100000)
            )
            begin
                @(negedge clk);

                timeout_cycles =
                    timeout_cycles + 1;
            end

            if (done_seen !== 1'b1)
            begin
                $display(
                    "TIMEOUT vector=%0d cycles=%0d busy=%0b butterflies=%0d",
                    vector_number,
                    timeout_cycles,
                    busy,
                    butterfly_count
                );

                $fatal(1);
            end

            if (busy !== 1'b0)
            begin
                $display(
                    "FAIL: busy remained asserted after vector %0d",
                    vector_number
                );

                $fatal(1);
            end

            if (
                butterfly_count
                !== 11'd1024
            )
            begin
                $display(
                    "FAIL: butterfly count vector=%0d result=%0d expected=1024",
                    vector_number,
                    butterfly_count
                );

                $fatal(1);
            end

            if (cycles == 32'd0)
            begin
                $display(
                    "FAIL: cycle count remained zero"
                );

                $fatal(1);
            end

            compare_result(vector_number);

            $display(
                "Vector %0d hardware-controller cycles: %0d",
                vector_number,
                cycles
            );

            if (vector_number == 0)
            begin
                first_cycle_count =
                    cycles;
            end
            else
            begin
                second_cycle_count =
                    cycles;
            end
        end
    endtask

    initial
    begin
        /*
         * These are already twisted and bit-reversed by the Python
         * golden model. This core tests only the cyclic NTT stage.
         */
        $readmemh(
            "../model/golden_n256/forward_a_bit_reversed_input.mem",
            input_a
        );

        $readmemh(
            "../model/golden_n256/forward_b_bit_reversed_input.mem",
            input_b
        );

        $readmemh(
            "../model/golden_n256/forward_a.mem",
            expected_a
        );

        $readmemh(
            "../model/golden_n256/forward_b.mem",
            expected_b
        );

        repeat (5) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        run_vector(0);
        run_vector(1);

        if (
            first_cycle_count
            !== second_cycle_count
        )
        begin
            $display(
                "FAIL: data-dependent timing first=%0d second=%0d",
                first_cycle_count,
                second_cycle_count
            );

            $fatal(1);
        end

        $display(
            "PASS: actual butterfly_core executed all 1024 butterflies"
        );

        $display(
            "PASS: two back-to-back N=256 cyclic NTTs agree with golden model"
        );

        $display(
            "Constant transform cycles: %0d",
            first_cycle_count
        );

        $display(
            "Modular multiplications per transform: %0d",
            NTT_BUTTERFLIES
        );

        $finish;
    end

endmodule
