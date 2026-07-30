`timescale 1ns/1ps

module tb_ntt4096_cyclic_core;

    localparam integer N =
        4096;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic forward_start =
        1'b0;

    logic forward_load_we =
        1'b0;

    logic [11:0] forward_load_addr =
        12'd0;

    logic [31:0] forward_load_data =
        32'd0;

    logic [11:0] forward_read_addr =
        12'd0;

    logic [31:0] forward_read_data;

    logic forward_busy;
    logic forward_done;

    logic [31:0] forward_cycles;
    logic [14:0] forward_butterfly_count;

    logic inverse_start =
        1'b0;

    logic inverse_load_we =
        1'b0;

    logic [11:0] inverse_load_addr =
        12'd0;

    logic [31:0] inverse_load_data =
        32'd0;

    logic [11:0] inverse_read_addr =
        12'd0;

    logic [31:0] inverse_read_data;

    logic inverse_busy;
    logic inverse_done;

    logic [31:0] inverse_cycles;
    logic [14:0] inverse_butterfly_count;

    logic [31:0] forward_input_a [0:N-1];
    logic [31:0] forward_input_b [0:N-1];
    logic [31:0] inverse_input [0:N-1];

    logic [31:0] expected_forward_a [0:N-1];
    logic [31:0] expected_forward_b [0:N-1];
    logic [31:0] expected_inverse [0:N-1];

    logic [31:0] first_forward_cycles;

    integer address;

    ntt4096_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            "../tests/fixtures/ntt_n4096/forward_twiddles.mem"
        )
    ) forward_dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (forward_start),

        .load_we         (forward_load_we),
        .load_addr       (forward_load_addr),
        .load_data       (forward_load_data),

        .read_addr       (forward_read_addr),
        .read_data       (forward_read_data),

        .busy            (forward_busy),
        .done            (forward_done),

        .cycles          (forward_cycles),
        .butterfly_count (forward_butterfly_count)
    );

    ntt4096_cyclic_core #(
        .TWIDDLE_INIT_FILE(
            "../tests/fixtures/ntt_n4096/inverse_twiddles.mem"
        )
    ) inverse_dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .start           (inverse_start),

        .load_we         (inverse_load_we),
        .load_addr       (inverse_load_addr),
        .load_data       (inverse_load_data),

        .read_addr       (inverse_read_addr),
        .read_data       (inverse_read_data),

        .busy            (inverse_busy),
        .done            (inverse_done),

        .cycles          (inverse_cycles),
        .butterfly_count (inverse_butterfly_count)
    );

    always #5 clk = ~clk;

    task automatic load_forward(
        input integer dataset
    );
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                forward_load_we =
                    1'b1;

                forward_load_addr =
                    address[11:0];

                if (dataset == 0)
                begin
                    forward_load_data =
                        forward_input_a[address];
                end
                else
                begin
                    forward_load_data =
                        forward_input_b[address];
                end

                @(posedge clk);
            end

            @(negedge clk);

            forward_load_we =
                1'b0;
        end
    endtask

    task automatic start_and_wait_forward;
        begin
            @(negedge clk);

            forward_start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            forward_start =
                1'b0;

            while (!forward_done)
            begin
                @(posedge clk);
                @(negedge clk);
            end

            if (
                forward_busy
                || forward_butterfly_count != 15'd24576
            )
            begin
                $display(
                    "FAIL FORWARD COMPLETION busy=%0b butterflies=%0d",
                    forward_busy,
                    forward_butterfly_count
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_forward(
        input integer dataset
    );
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                forward_read_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (dataset == 0)
                begin
                    if (
                        forward_read_data
                        !== expected_forward_a[address]
                    )
                    begin
                        $display(
                            "FAIL FORWARD A address=%0d result=%0d expected=%0d",
                            address,
                            forward_read_data,
                            expected_forward_a[address]
                        );

                        $fatal(1);
                    end
                end
                else
                begin
                    if (
                        forward_read_data
                        !== expected_forward_b[address]
                    )
                    begin
                        $display(
                            "FAIL FORWARD B address=%0d result=%0d expected=%0d",
                            address,
                            forward_read_data,
                            expected_forward_b[address]
                        );

                        $fatal(1);
                    end
                end
            end
        end
    endtask

    task automatic load_inverse;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                inverse_load_we =
                    1'b1;

                inverse_load_addr =
                    address[11:0];

                inverse_load_data =
                    inverse_input[address];

                @(posedge clk);
            end

            @(negedge clk);

            inverse_load_we =
                1'b0;
        end
    endtask

    task automatic start_and_wait_inverse;
        begin
            @(negedge clk);

            inverse_start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            inverse_start =
                1'b0;

            while (!inverse_done)
            begin
                @(posedge clk);
                @(negedge clk);
            end

            if (
                inverse_busy
                || inverse_butterfly_count != 15'd24576
            )
            begin
                $display(
                    "FAIL INVERSE COMPLETION busy=%0b butterflies=%0d",
                    inverse_busy,
                    inverse_butterfly_count
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_inverse;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                inverse_read_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (
                    inverse_read_data
                    !== expected_inverse[address]
                )
                begin
                    $display(
                        "FAIL INVERSE address=%0d result=%0d expected=%0d",
                        address,
                        inverse_read_data,
                        expected_inverse[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a_bit_reversed.mem",
            forward_input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_b_bit_reversed.mem",
            forward_input_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_product_bit_reversed.mem",
            inverse_input
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a.mem",
            expected_forward_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_b.mem",
            expected_forward_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_product_cyclic.mem",
            expected_inverse
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_forward(0);
        start_and_wait_forward();
        compare_forward(0);

        first_forward_cycles =
            forward_cycles;

        $display(
            "PASS: N=4096 forward cyclic NTT A matches golden model"
        );

        $display(
            "Forward cyclic cycles: %0d",
            forward_cycles
        );

        load_forward(1);
        start_and_wait_forward();
        compare_forward(1);

        if (
            forward_cycles
            !== first_forward_cycles
        )
        begin
            $display(
                "FAIL FORWARD CONSTANT TIME first=%0d second=%0d",
                first_forward_cycles,
                forward_cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: N=4096 forward cyclic NTT B matches golden model"
        );

        load_inverse();
        start_and_wait_inverse();
        compare_inverse();

        if (
            inverse_cycles
            !== first_forward_cycles
        )
        begin
            $display(
                "FAIL DIRECTION TIMING forward=%0d inverse=%0d",
                first_forward_cycles,
                inverse_cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: N=4096 inverse cyclic NTT matches golden model"
        );

        $display(
            "PASS: forward A, forward B, and inverse timing are constant"
        );

        $display(
            "Butterflies per transform: 24576"
        );

        $display(
            "Exact cyclic-transform cycles: %0d",
            first_forward_cycles
        );

        $finish;
    end

endmodule
