`timescale 1ns/1ps

module tb_pointwise_mul4096_core;

    localparam integer N =
        4096;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic load_a_we =
        1'b0;

    logic [11:0] load_a_addr =
        12'd0;

    logic [31:0] load_a_data =
        32'd0;

    logic load_b_we =
        1'b0;

    logic [11:0] load_b_addr =
        12'd0;

    logic [31:0] load_b_data =
        32'd0;

    logic [11:0] read_addr =
        12'd0;

    logic [31:0] read_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [12:0] multiplication_count;

    logic [31:0] forward_a [0:N-1];
    logic [31:0] forward_b [0:N-1];
    logic [31:0] expected_pointwise [0:N-1];

    logic [31:0] first_cycles;

    integer address;

    pointwise_mul4096_core dut (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (start),

        .load_a_we            (load_a_we),
        .load_a_addr          (load_a_addr),
        .load_a_data          (load_a_data),

        .load_b_we            (load_b_we),
        .load_b_addr          (load_b_addr),
        .load_b_data          (load_b_data),

        .read_addr            (read_addr),
        .read_data            (read_data),

        .busy                 (busy),
        .done                 (done),

        .cycles               (cycles),
        .multiplication_count (multiplication_count)
    );

    always #5 clk = ~clk;

    task automatic load_inputs;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                load_a_we =
                    1'b1;

                load_a_addr =
                    address[11:0];

                load_a_data =
                    forward_a[address];

                load_b_we =
                    1'b1;

                load_b_addr =
                    address[11:0];

                load_b_data =
                    forward_b[address];

                @(posedge clk);
            end

            @(negedge clk);

            load_a_we =
                1'b0;

            load_b_we =
                1'b0;
        end
    endtask

    task automatic run_pointwise;
        begin
            @(negedge clk);

            start =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            start =
                1'b0;

            while (!done)
            begin
                @(posedge clk);
                @(negedge clk);
            end

            if (
                busy
                || multiplication_count != 13'd4096
            )
            begin
                $display(
                    "FAIL COMPLETION busy=%0b multiplications=%0d",
                    busy,
                    multiplication_count
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_result;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                read_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (
                    read_data
                    !== expected_pointwise[address]
                )
                begin
                    $display(
                        "FAIL POINTWISE address=%0d result=%0d expected=%0d",
                        address,
                        read_data,
                        expected_pointwise[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a.mem",
            forward_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_b.mem",
            forward_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/pointwise.mem",
            expected_pointwise
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_inputs();
        run_pointwise();
        compare_result();

        first_cycles =
            cycles;

        $display(
            "PASS: all 4096 N=4096 pointwise modular products"
        );

        $display(
            "Pointwise multiplication cycles: %0d",
            cycles
        );

        load_inputs();
        run_pointwise();
        compare_result();

        if (cycles !== first_cycles)
        begin
            $display(
                "FAIL CONSTANT TIME first=%0d second=%0d",
                first_cycles,
                cycles
            );

            $fatal(1);
        end

        $display(
            "PASS: repeated pointwise phase is constant-time and correct"
        );

        $display(
            "Modular multiplications: 4096"
        );

        $display(
            "Exact pointwise-phase cycles: %0d",
            first_cycles
        );

        $finish;
    end

endmodule
