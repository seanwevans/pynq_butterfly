`timescale 1ns/1ps

module tb_inverse_ntt16_core;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    localparam logic [31:0] OPENFHE_PSI_INVERSE =
        32'd751566494;

    localparam logic [31:0] OPENFHE_OMEGA_INVERSE =
        32'd155190050;

    localparam logic [31:0] OPENFHE_N_INVERSE =
        32'd1006586881;

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

    logic [31:0] transform_input [0:15];
    logic [31:0] expected_output [0:15];

    integer i;
    integer timeout_cycles;

    inverse_ntt16_core dut (
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
            "../model/golden/forward_a.mem",
            transform_input
        );

        $readmemh(
            "../model/golden/input_a.mem",
            expected_output
        );
    end

    task automatic check_output;
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

                if (read_data !== expected_output[address])
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
                "PASS: complete N=16 inverse negacyclic NTT matches golden model"
            );
        end
    endtask

    initial
    begin
        repeat (4) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * Load the natural-order forward NTT output.
         */
        for (i = 0; i < 16; i = i + 1)
        begin
            @(negedge clk);

            load_we   = 1'b1;
            load_addr = i;
            load_data = transform_input[i];
        end

        @(negedge clk);
        load_we = 1'b0;

        $display(
            "PASS: loaded 16 natural-order transform coefficients"
        );

        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        timeout_cycles = 0;

        while (
            (done_seen !== 1'b1) &&
            (timeout_cycles < 5000)
        )
        begin
            @(negedge clk);
            timeout_cycles = timeout_cycles + 1;
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

        if (busy !== 1'b0)
        begin
            $display(
                "FAIL: busy remained asserted after completion"
            );

            $fatal(1);
        end

        check_output();

        $display(
            "OpenFHE q=%0d psi_inverse=%0d omega_inverse=%0d N_inverse=%0d",
            OPENFHE_Q,
            OPENFHE_PSI_INVERSE,
            OPENFHE_OMEGA_INVERSE,
            OPENFHE_N_INVERSE
        );

        $display(
            "Inverse cyclic butterflies executed: 32"
        );

        $display(
            "Scale and untwist multiplications executed: 16"
        );

        $display(
            "Observed testbench cycles: %0d",
            timeout_cycles
        );

        $finish;
    end

endmodule
