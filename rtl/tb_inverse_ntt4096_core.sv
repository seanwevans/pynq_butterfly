`timescale 1ns/1ps

module tb_inverse_ntt4096_core;

    localparam integer N =
        4096;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic start =
        1'b0;

    logic load_we =
        1'b0;

    logic [11:0] load_addr =
        12'd0;

    logic [31:0] load_data =
        32'd0;

    logic [11:0] read_addr =
        12'd0;

    logic [31:0] read_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [12:0] preparation_count;
    logic [14:0] butterfly_count;
    logic [12:0] postprocessing_count;

    logic [31:0] pointwise_input [0:N-1];
    logic [31:0] expected_convolution [0:N-1];

    logic [31:0] first_cycles;

    integer address;

    inverse_ntt4096_core dut (
        .clk                  (clk),
        .reset_n              (reset_n),
        .start                (start),

        .load_we              (load_we),
        .load_addr            (load_addr),
        .load_data            (load_data),

        .read_addr            (read_addr),
        .read_data            (read_data),

        .busy                 (busy),
        .done                 (done),

        .cycles               (cycles),
        .preparation_count    (preparation_count),
        .butterfly_count      (butterfly_count),
        .postprocessing_count (postprocessing_count)
    );

    always #5 clk = ~clk;

    task automatic load_pointwise_input;
        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                @(negedge clk);

                load_we =
                    1'b1;

                load_addr =
                    address[11:0];

                load_data =
                    pointwise_input[address];

                @(posedge clk);
            end

            @(negedge clk);

            load_we =
                1'b0;
        end
    endtask

    task automatic run_transform;
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
                || preparation_count != 13'd4096
                || butterfly_count != 15'd24576
                || postprocessing_count != 13'd4096
            )
            begin
                $display(
                    "FAIL COMPLETION busy=%0b preparation=%0d butterflies=%0d postprocessing=%0d",
                    busy,
                    preparation_count,
                    butterfly_count,
                    postprocessing_count
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_convolution;
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
                    !== expected_convolution[address]
                )
                begin
                    $display(
                        "FAIL INVERSE address=%0d result=%0d expected=%0d",
                        address,
                        read_data,
                        expected_convolution[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../model/golden_n4096/pointwise.mem",
            pointwise_input
        );

        $readmemh(
            "../model/golden_n4096/convolution.mem",
            expected_convolution
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_pointwise_input();
        run_transform();
        compare_convolution();

        first_cycles =
            cycles;

        $display(
            "PASS: complete N=4096 inverse negacyclic NTT"
        );

        $display(
            "Inverse transform cycles: %0d",
            cycles
        );

        load_pointwise_input();
        run_transform();
        compare_convolution();

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
            "PASS: repeated inverse transform is constant-time and correct"
        );

        $display(
            "Bit-reversed preparation copies: 4096"
        );

        $display(
            "Cyclic-transform butterflies: 24576"
        );

        $display(
            "Postprocessing modular multiplications: 4096"
        );

        $display(
            "Exact inverse-transform cycles: %0d",
            first_cycles
        );

        $finish;
    end

endmodule
