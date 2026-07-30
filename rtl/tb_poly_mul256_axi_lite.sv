`timescale 1ns/1ps

module tb_poly_mul256_axi_lite;

    localparam logic [1:0] AXI_OKAY =
        2'b00;

    localparam logic [1:0] AXI_SLVERR =
        2'b10;

    localparam logic [15:0] REG_CONTROL =
        16'h0000;

    localparam logic [15:0] REG_STATUS =
        16'h0004;

    localparam logic [15:0] REG_CYCLES =
        16'h0008;

    localparam logic [15:0] REG_VERSION =
        16'h000c;

    localparam logic [15:0] REG_MODULUS =
        16'h0010;

    localparam logic [15:0] REG_N =
        16'h0014;

    localparam logic [15:0] REG_MULTS =
        16'h0018;

    localparam logic [15:0] A_BASE =
        16'h0100;

    localparam logic [15:0] B_BASE =
        16'h0500;

    localparam logic [15:0] RESULT_BASE =
        16'h0900;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    logic clk =
        1'b0;

    logic reset_n =
        1'b0;

    logic [15:0] awaddr =
        16'd0;

    logic [2:0] awprot =
        3'b000;

    logic awvalid =
        1'b0;

    wire awready;

    logic [31:0] wdata =
        32'd0;

    logic [3:0] wstrb =
        4'hf;

    logic wvalid =
        1'b0;

    wire wready;

    wire [1:0] bresp;
    wire bvalid;

    logic bready =
        1'b1;

    logic [15:0] araddr =
        16'd0;

    logic [2:0] arprot =
        3'b000;

    logic arvalid =
        1'b0;

    wire arready;

    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;

    logic rready =
        1'b1;

    logic [31:0] input_a [0:255];
    logic [31:0] input_b [0:255];
    logic [31:0] expected [0:255];

    logic [1:0] response;
    logic [31:0] read_value;

    integer address;
    integer polls;

    logic [31:0] first_cycle_count;
    logic [31:0] second_cycle_count;

    poly_mul256_axi_lite #(
        .FORWARD_TWIST_INIT_FILE(
            "../tests/fixtures/ntt_n256/twist_factors.mem"
        ),

        .FORWARD_TWIDDLE_INIT_FILE(
            "../tests/fixtures/ntt_n256/forward_twiddles.mem"
        ),

        .INVERSE_TWIDDLE_INIT_FILE(
            "../tests/fixtures/ntt_n256/inverse_twiddles.mem"
        ),

        .INVERSE_SCALE_INIT_FILE(
            "../tests/fixtures/ntt_n256/inverse_scale_factors.mem"
        )
    ) dut (
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (reset_n),

        .S_AXI_AWADDR  (awaddr),
        .S_AXI_AWPROT  (awprot),
        .S_AXI_AWVALID (awvalid),
        .S_AXI_AWREADY (awready),

        .S_AXI_WDATA   (wdata),
        .S_AXI_WSTRB   (wstrb),
        .S_AXI_WVALID  (wvalid),
        .S_AXI_WREADY  (wready),

        .S_AXI_BRESP   (bresp),
        .S_AXI_BVALID  (bvalid),
        .S_AXI_BREADY  (bready),

        .S_AXI_ARADDR  (araddr),
        .S_AXI_ARPROT  (arprot),
        .S_AXI_ARVALID (arvalid),
        .S_AXI_ARREADY (arready),

        .S_AXI_RDATA   (rdata),
        .S_AXI_RRESP   (rresp),
        .S_AXI_RVALID  (rvalid),
        .S_AXI_RREADY  (rready)
    );

    always #5 clk = ~clk;

    task automatic send_aw(
        input logic [15:0] address_value
    );
        begin
            @(negedge clk);

            awaddr =
                address_value;

            awvalid =
                1'b1;

            while (!(awvalid && awready))
                @(posedge clk);

            @(negedge clk);

            awvalid =
                1'b0;
        end
    endtask

    task automatic send_w(
        input logic [31:0] value,
        input logic [3:0] strobes
    );
        begin
            @(negedge clk);

            wdata =
                value;

            wstrb =
                strobes;

            wvalid =
                1'b1;

            while (!(wvalid && wready))
                @(posedge clk);

            @(negedge clk);

            wvalid =
                1'b0;
        end
    endtask

    /*
     * order:
     *
     *   0 = AW and W together
     *   1 = AW before W
     *   2 = W before AW
     */
    task automatic axi_write(
        input logic [15:0] address_value,
        input logic [31:0] value,
        input logic [3:0] strobes,
        input integer order,
        output logic [1:0] write_response
    );
        integer aw_done;
        integer w_done;

        begin
            if (order == 1)
            begin
                send_aw(address_value);
                send_w(value, strobes);
            end
            else if (order == 2)
            begin
                send_w(value, strobes);
                send_aw(address_value);
            end
            else
            begin
                aw_done =
                    0;

                w_done =
                    0;

                @(negedge clk);

                awaddr =
                    address_value;

                awvalid =
                    1'b1;

                wdata =
                    value;

                wstrb =
                    strobes;

                wvalid =
                    1'b1;

                while (
                    !aw_done ||
                    !w_done
                )
                begin
                    @(posedge clk);

                    if (
                        awvalid &&
                        awready
                    )
                    begin
                        aw_done =
                            1;
                    end

                    if (
                        wvalid &&
                        wready
                    )
                    begin
                        w_done =
                            1;
                    end

                    @(negedge clk);

                    if (aw_done)
                        awvalid = 1'b0;

                    if (w_done)
                        wvalid = 1'b0;
                end
            end

            while (bvalid !== 1'b1)
                @(posedge clk);

            write_response =
                bresp;

            @(posedge clk);
        end
    endtask

    task automatic axi_read(
        input logic [15:0] address_value,
        output logic [31:0] value,
        output logic [1:0] read_response
    );
        begin
            @(negedge clk);

            araddr =
                address_value;

            arvalid =
                1'b1;

            while (!(arvalid && arready))
                @(posedge clk);

            @(negedge clk);

            arvalid =
                1'b0;

            while (rvalid !== 1'b1)
                @(posedge clk);

            value =
                rdata;

            read_response =
                rresp;

            @(posedge clk);
        end
    endtask

    task automatic require_okay(
        input logic [1:0] actual,
        input integer operation_number
    );
        begin
            if (actual !== AXI_OKAY)
            begin
                $display(
                    "FAIL AXI response operation=%0d response=%0b",
                    operation_number,
                    actual
                );

                $fatal(1);
            end
        end
    endtask

    task automatic wait_for_completion;
        begin
            polls =
                0;

            read_value =
                32'd0;

            while (
                !read_value[1] &&
                polls < 100000
            )
            begin
                axi_read(
                    REG_STATUS,
                    read_value,
                    response
                );

                require_okay(
                    response,
                    1000
                );

                polls =
                    polls + 1;
            end

            if (!read_value[1])
            begin
                $display(
                    "FAIL: completion not observed polls=%0d",
                    polls
                );

                $fatal(1);
            end

            if (read_value[0])
            begin
                $display(
                    "FAIL: busy remained asserted after completion"
                );

                $fatal(1);
            end
        end
    endtask

    task automatic compare_result_window;
        begin
            for (
                address = 0;
                address < 256;
                address = address + 1
            )
            begin
                axi_read(
                    RESULT_BASE + (address * 4),
                    read_value,
                    response
                );

                require_okay(
                    response,
                    2000 + address
                );

                if (
                    read_value
                    !== expected[address]
                )
                begin
                    $display(
                        "FAIL RESULT address=%0d result=%0d expected=%0d",
                        address,
                        read_value,
                        expected[address]
                    );

                    $fatal(1);
                end
            end
        end
    endtask

    initial
    begin
        $readmemh(
            "../tests/fixtures/ntt_n256/input_a.mem",
            input_a
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/input_b.mem",
            input_b
        );

        $readmemh(
            "../tests/fixtures/ntt_n256/convolution.mem",
            expected
        );

        repeat (5) @(posedge clk);

        @(negedge clk);

        reset_n =
            1'b1;

        /*
         * Fixed identification registers.
         */
        axi_read(
            REG_VERSION,
            read_value,
            response
        );

        require_okay(response, 0);

        if (read_value !== 32'h0002_0000)
        begin
            $display(
                "FAIL VERSION result=%08x expected=00020000",
                read_value
            );

            $fatal(1);
        end

        axi_read(
            REG_MODULUS,
            read_value,
            response
        );

        require_okay(response, 1);

        if (read_value !== OPENFHE_Q)
        begin
            $display(
                "FAIL MODULUS result=%0d expected=%0d",
                read_value,
                OPENFHE_Q
            );

            $fatal(1);
        end

        axi_read(
            REG_N,
            read_value,
            response
        );

        require_okay(response, 2);

        if (read_value !== 32'd256)
        begin
            $display(
                "FAIL N result=%0d expected=256",
                read_value
            );

            $fatal(1);
        end

        axi_read(
            REG_MULTS,
            read_value,
            response
        );

        require_okay(response, 3);

        if (read_value !== 32'd4096)
        begin
            $display(
                "FAIL MULTS result=%0d expected=4096",
                read_value
            );

            $fatal(1);
        end

        $display(
            "PASS: N=256 identification registers"
        );

        /*
         * Load both complete source polynomials while exercising all
         * three legal AW/W arrival orders.
         */
        for (
            address = 0;
            address < 256;
            address = address + 1
        )
        begin
            axi_write(
                A_BASE + (address * 4),
                input_a[address],
                4'hf,
                address % 3,
                response
            );

            require_okay(
                response,
                10 + address
            );
        end

        for (
            address = 0;
            address < 256;
            address = address + 1
        )
        begin
            axi_write(
                B_BASE + (address * 4),
                input_b[address],
                4'hf,
                (address + 1) % 3,
                response
            );

            require_okay(
                response,
                300 + address
            );
        end

        $display(
            "PASS: loaded 512 coefficients through AXI-Lite"
        );

        /*
         * Source windows are write-only.
         */
        axi_read(
            A_BASE,
            read_value,
            response
        );

        if (response !== AXI_SLVERR)
        begin
            $display(
                "FAIL: source read response=%0b expected=10",
                response
            );

            $fatal(1);
        end

        /*
         * Partial writes are deliberately rejected.
         */
        axi_write(
            A_BASE,
            32'h12345678,
            4'b0001,
            1,
            response
        );

        if (response !== AXI_SLVERR)
        begin
            $display(
                "FAIL: partial write response=%0b expected=10",
                response
            );

            $fatal(1);
        end

        $display(
            "PASS: write-only windows and full-word write policy"
        );

        /*
         * Start the complete N=256 polynomial product.
         */
        axi_write(
            REG_CONTROL,
            32'd1,
            4'hf,
            0,
            response
        );

        require_okay(response, 600);

        /*
         * Confirm busy becomes visible.
         */
        polls =
            0;

        read_value =
            32'd0;

        while (
            !read_value[0] &&
            polls < 100
        )
        begin
            axi_read(
                REG_STATUS,
                read_value,
                response
            );

            require_okay(
                response,
                601
            );

            polls =
                polls + 1;
        end

        if (!read_value[0])
        begin
            $display(
                "FAIL: busy was never observed"
            );

            $fatal(1);
        end

        /*
         * Writes are protected while the engine is active.
         */
        axi_write(
            A_BASE,
            32'd123,
            4'hf,
            2,
            response
        );

        if (response !== AXI_SLVERR)
        begin
            $display(
                "FAIL: write while busy response=%0b expected=10",
                response
            );

            $fatal(1);
        end

        $display(
            "PASS: writes are rejected while N=256 engine is busy"
        );

        wait_for_completion();

        axi_read(
            REG_CYCLES,
            first_cycle_count,
            response
        );

        require_okay(response, 700);

        if (
            first_cycle_count
            !== 32'd93713
        )
        begin
            $display(
                "FAIL CYCLES result=%0d expected=93713",
                first_cycle_count
            );

            $fatal(1);
        end

        $display(
            "PASS: status, sticky completion, and cycle counter"
        );

        $display(
            "Hardware-reported cycles: %0d",
            first_cycle_count
        );

        compare_result_window();

        $display(
            "PASS: all 256 AXI result words match golden convolution"
        );

        /*
         * Clear completion and run the same loaded operands again.
         */
        axi_write(
            REG_CONTROL,
            32'd2,
            4'hf,
            1,
            response
        );

        require_okay(response, 800);

        axi_read(
            REG_STATUS,
            read_value,
            response
        );

        require_okay(response, 801);

        if (read_value[1])
        begin
            $display(
                "FAIL: sticky completion did not clear"
            );

            $fatal(1);
        end

        axi_write(
            REG_CONTROL,
            32'd1,
            4'hf,
            2,
            response
        );

        require_okay(response, 802);

        wait_for_completion();

        axi_read(
            REG_CYCLES,
            second_cycle_count,
            response
        );

        require_okay(response, 803);

        if (
            second_cycle_count
            !== first_cycle_count
        )
        begin
            $display(
                "FAIL: repeat timing first=%0d second=%0d",
                first_cycle_count,
                second_cycle_count
            );

            $fatal(1);
        end

        compare_result_window();

        $display(
            "PASS: repeated AXI operation is constant-time and correct"
        );

        /*
         * Unmapped addresses return SLVERR.
         */
        axi_read(
            16'h0d00,
            read_value,
            response
        );

        if (response !== AXI_SLVERR)
        begin
            $display(
                "FAIL: unmapped read response=%0b expected=10",
                response
            );

            $fatal(1);
        end

        $display(
            "PASS: AXI-Lite error responses"
        );

        $display(
            "PASS: complete N=256 polynomial multiplier AXI-Lite peripheral verified"
        );

        $display(
            "Register span used: 0x0000-0x0CFC"
        );

        $display(
            "Polynomial-product cycles: %0d",
            first_cycle_count
        );

        $finish;
    end

endmodule
