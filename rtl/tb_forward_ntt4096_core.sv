`timescale 1ns/1ps

module tb_forward_ntt4096_core;

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
    logic [12:0] preprocessing_count;
    logic [14:0] butterfly_count;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];

    logic [31:0] expected_a [0:N-1];
    logic [31:0] expected_b [0:N-1];

    logic [31:0] first_cycles;

    integer address;

    forward_ntt4096_core dut (
        .clk                 (clk),
        .reset_n             (reset_n),
        .start               (start),

        .load_we             (load_we),
        .load_addr           (load_addr),
        .load_data           (load_data),

        .read_addr           (read_addr),
        .read_data           (read_data),

        .busy                (busy),
        .done                (done),

        .cycles              (cycles),
        .preprocessing_count (preprocessing_count),
        .butterfly_count     (butterfly_count)
    );

    always #5 clk = ~clk;

    task automatic load_dataset(
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

                load_we =
                    1'b1;

                load_addr =
                    address[11:0];

                if (dataset == 0)
                begin
                    load_data =
                        input_a[address];
                end
                else
                begin
                    load_data =
                        input_b[address];
                end

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
                || preprocessing_count != 13'd4096
                || butterfly_count != 15'd24576
            )
            begin
                $display(
                    "FAIL COMPLETION busy=%0b preprocessing=%0d butterflies=%0d",
                    busy,
                    preprocessing_count,
                    butterfly_count
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_dataset(
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

                read_addr =
                    address[11:0];

                @(posedge clk);
                @(negedge clk);

                if (dataset == 0)
                begin
                    if (
                        read_data
                        !== expected_a[address]
                    )
                    begin
                        $display(
                            "FAIL FORWARD A address=%0d result=%0d expected=%0d",
                            address,
                            read_data,
                            expected_a[address]
                        );

                        $fatal(1);
                    end
                end
                else
                begin
                    if (
                        read_data
                        !== expected_b[address]
                    )
                    begin
                        $display(
                            "FAIL FORWARD B address=%0d result=%0d expected=%0d",
                            address,
                            read_data,
                            expected_b[address]
                        );

                        $fatal(1);
                    end
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n4096/input_a.mem",
            input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/input_b.mem",
            input_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_a.mem",
            expected_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n4096/forward_b.mem",
            expected_b
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        load_dataset(0);
        run_transform();
        compare_dataset(0);

        first_cycles =
            cycles;

        $display(
            "PASS: complete N=4096 forward negacyclic NTT A"
        );

        $display(
            "Forward transform cycles: %0d",
            cycles
        );

        load_dataset(1);
        run_transform();
        compare_dataset(1);

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
            "PASS: complete N=4096 forward negacyclic NTT B"
        );

        $display(
            "PASS: two complete forward transforms are constant-time"
        );

        $display(
            "Preprocessing modular multiplications: 4096"
        );

        $display(
            "Cyclic-transform butterflies: 24576"
        );

        $display(
            "Exact forward-transform cycles: %0d",
            first_cycles
        );

        $finish;
    end

endmodule
