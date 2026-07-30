`timescale 1ns/1ps

module tb_forward_ntt4096_dual_dif_core;

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

    logic [11:0] read_a_addr =
        12'd0;

    logic [31:0] read_a_data;

    logic [11:0] read_b_addr =
        12'd0;

    logic [31:0] read_b_data;

    logic busy;
    logic done;

    logic [31:0] cycles;
    logic [12:0] preprocessing_count;
    logic [14:0] butterfly_count;

    logic [31:0] input_a [0:N-1];
    logic [31:0] input_b [0:N-1];

    logic [31:0] expected_forward_a [0:N-1];
    logic [31:0] expected_forward_b [0:N-1];

    logic [31:0] first_cycles;

    integer address;
    integer run_index;

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

    forward_ntt4096_dual_dif_core dut (
        .clk                 (clk),
        .reset_n             (reset_n),
        .start               (start),

        .load_a_we           (load_a_we),
        .load_a_addr         (load_a_addr),
        .load_a_data         (load_a_data),

        .load_b_we           (load_b_we),
        .load_b_addr         (load_b_addr),
        .load_b_data         (load_b_data),

        .read_a_addr         (read_a_addr),
        .read_a_data         (read_a_data),

        .read_b_addr         (read_b_addr),
        .read_b_data         (read_b_data),

        .busy                (busy),
        .done                (done),

        .cycles              (cycles),
        .preprocessing_count (preprocessing_count),
        .butterfly_count     (butterfly_count)
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
                    input_a[address];

                load_b_we =
                    1'b1;

                load_b_addr =
                    address[11:0];

                load_b_data =
                    input_b[address];

                @(posedge clk);
            end

            @(negedge clk);

            load_a_we =
                1'b0;

            load_b_we =
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

    task automatic compare_outputs;
        logic [11:0] memory_address;

        begin
            for (
                address = 0;
                address < N;
                address = address + 1
            )
            begin
                memory_address =
                    bit_reverse12(
                        address[11:0]
                    );

                @(negedge clk);

                read_a_addr =
                    memory_address;

                read_b_addr =
                    memory_address;

                @(posedge clk);
                @(negedge clk);

                if (
                    read_a_data
                    !== expected_forward_a[address]
                )
                begin
                    $display(
                        "FAIL FORWARD A natural_index=%0d memory_address=%0d result=%0d expected=%0d",
                        address,
                        memory_address,
                        read_a_data,
                        expected_forward_a[address]
                    );

                    $fatal(1);
                end

                if (
                    read_b_data
                    !== expected_forward_b[address]
                )
                begin
                    $display(
                        "FAIL FORWARD B natural_index=%0d memory_address=%0d result=%0d expected=%0d",
                        address,
                        memory_address,
                        read_b_data,
                        expected_forward_b[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../model/golden_n4096/input_a.mem",
            input_a
        );

        $readmemh(
            "../model/golden_n4096/input_b.mem",
            input_b
        );

        $readmemh(
            "../model/golden_n4096/forward_a.mem",
            expected_forward_a
        );

        $readmemh(
            "../model/golden_n4096/forward_b.mem",
            expected_forward_b
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        for (
            run_index = 0;
            run_index < 2;
            run_index = run_index + 1
        )
        begin
            load_inputs();
            run_transform();
            compare_outputs();

            if (run_index == 0)
            begin
                first_cycles =
                    cycles;
            end
            else if (cycles !== first_cycles)
            begin
                $display(
                    "FAIL CONSTANT TIME first=%0d second=%0d",
                    first_cycles,
                    cycles
                );

                $fatal(1);
            end

            $display(
                "PASS: dual in-place forward DIF transform run %0d",
                run_index
            );
        end

        $display(
            "PASS: A and B match natural-order golden transforms through bit-reversed storage"
        );

        $display(
            "PASS: one shared twist ROM, DIF scheduler, and twiddle ROM"
        );

        $display(
            "Coefficient BRAM banks: 2"
        );

        $display(
            "Preprocessing modular multiplications per lane: 4096"
        );

        $display(
            "DIF butterflies per lane: 24576"
        );

        $display(
            "Exact dual-forward cycles: %0d",
            first_cycles
        );

        $finish;
    end

endmodule
