`timescale 1ns/1ps

module tb_ntt4096_dif_cyclic_core;

    localparam integer N =
        4096;

    localparam logic [31:0] EXPECTED_CYCLES =
        32'd540673;

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

    logic [31:0] forward_input [0:N-1];
    logic [31:0] inverse_input [0:N-1];

    logic [31:0] expected_forward_natural [0:N-1];
    logic [31:0] expected_inverse_natural [0:N-1];

    integer address;

    function automatic logic [11:0] bit_reverse12(
        input logic [11:0] value
    );
        begin
            bit_reverse12 =
            {
                value[0],
                value[1],
                value[2],
                value[3],
                value[4],
                value[5],
                value[6],
                value[7],
                value[8],
                value[9],
                value[10],
                value[11]
            };
        end
    endfunction

    ntt4096_dif_cyclic_core #(
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

    ntt4096_dif_cyclic_core #(
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

    task automatic load_forward_input;
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

                forward_load_data =
                    forward_input[address];

                @(posedge clk);
            end

            @(negedge clk);

            forward_load_we =
                1'b0;
        end
    endtask

    task automatic load_inverse_input;
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

    task automatic run_forward;
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
                || forward_cycles !== EXPECTED_CYCLES
            )
            begin
                $display(
                    "FAIL FORWARD COMPLETION busy=%0b butterflies=%0d cycles=%0d",
                    forward_busy,
                    forward_butterfly_count,
                    forward_cycles
                );

                $fatal(1);
            end
        end
    endtask

    task automatic run_inverse;
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
                || inverse_cycles !== EXPECTED_CYCLES
            )
            begin
                $display(
                    "FAIL INVERSE COMPLETION busy=%0b butterflies=%0d cycles=%0d",
                    inverse_busy,
                    inverse_butterfly_count,
                    inverse_cycles
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_forward_bit_reversed;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                forward_read_addr =
                    bit_reverse12(
                        address[11:0]
                    );

                @(posedge clk);
                @(negedge clk);

                if (
                    forward_read_data
                    !== expected_forward_natural[address]
                )
                begin
                    $display(
                        "FAIL FORWARD DIF natural_index=%0d memory_address=%0d result=%0d expected=%0d",
                        address,
                        bit_reverse12(address[11:0]),
                        forward_read_data,
                        expected_forward_natural[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    task automatic compare_inverse_bit_reversed;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                inverse_read_addr =
                    bit_reverse12(
                        address[11:0]
                    );

                @(posedge clk);
                @(negedge clk);

                if (
                    inverse_read_data
                    !== expected_inverse_natural[address]
                )
                begin
                    $display(
                        "FAIL INVERSE DIF natural_index=%0d memory_address=%0d result=%0d expected=%0d",
                        address,
                        bit_reverse12(address[11:0]),
                        inverse_read_data,
                        expected_inverse_natural[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a_twisted_natural.mem",
            forward_input
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/pointwise.mem",
            inverse_input
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a.mem",
            expected_forward_natural
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/inverse_product_cyclic.mem",
            expected_inverse_natural
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_forward_input();
        run_forward();
        compare_forward_bit_reversed();

        $display(
            "PASS: forward DIF natural input produces bit-reversed golden output"
        );

        load_inverse_input();
        run_inverse();
        compare_inverse_bit_reversed();

        $display(
            "PASS: inverse DIF natural input produces bit-reversed golden output"
        );

        if (
            forward_cycles
            !== inverse_cycles
        )
        begin
            $display(
                "FAIL DIRECTION TIMING forward=%0d inverse=%0d",
                forward_cycles,
                inverse_cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: forward and inverse DIF timing is constant"
        );

        $display(
            "Butterflies per transform: 24576"
        );

        $display(
            "Exact DIF cyclic-transform cycles: %0d",
            forward_cycles
        );

        $finish;
    end

endmodule
