`timescale 1ns/1ps

module tb_poly_mul16_axi_lite;

    localparam logic [1:0] AXI_OKAY =
        2'b00;

    localparam logic [1:0] AXI_SLVERR =
        2'b10;

    localparam logic [7:0] REG_CONTROL = 8'h00;
    localparam logic [7:0] REG_STATUS  = 8'h04;
    localparam logic [7:0] REG_CYCLES  = 8'h08;
    localparam logic [7:0] REG_VERSION = 8'h0c;
    localparam logic [7:0] REG_MODULUS = 8'h10;
    localparam logic [7:0] REG_N       = 8'h14;
    localparam logic [7:0] REG_MULTS   = 8'h18;

    localparam logic [7:0] A_BASE =
        8'h20;

    localparam logic [7:0] B_BASE =
        8'h60;

    localparam logic [7:0] RESULT_BASE =
        8'ha0;

    localparam logic [31:0] OPENFHE_Q =
        32'd1073692673;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic [7:0]  awaddr = 8'd0;
    logic [2:0]  awprot = 3'b000;
    logic        awvalid = 1'b0;
    wire         awready;

    logic [31:0] wdata = 32'd0;
    logic [3:0]  wstrb = 4'hf;
    logic        wvalid = 1'b0;
    wire         wready;

    wire [1:0] bresp;
    wire       bvalid;
    logic      bready = 1'b1;

    logic [7:0] araddr = 8'd0;
    logic [2:0] arprot = 3'b000;
    logic       arvalid = 1'b0;
    wire        arready;

    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    logic       rready = 1'b1;

    logic [31:0] input_a [0:15];
    logic [31:0] input_b [0:15];
    logic [31:0] expected [0:15];

    logic [1:0]  response;
    logic [31:0] read_value;

    integer i;
    integer polls;

    poly_mul16_axi_lite dut (
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
        input logic [7:0] address
    );
        begin
            @(negedge clk);

            awaddr  = address;
            awvalid = 1'b1;

            while (!(awvalid && awready))
                @(posedge clk);

            @(negedge clk);
            awvalid = 1'b0;
        end
    endtask

    task automatic send_w(
        input logic [31:0] value
    );
        begin
            @(negedge clk);

            wdata  = value;
            wstrb  = 4'hf;
            wvalid = 1'b1;

            while (!(wvalid && wready))
                @(posedge clk);

            @(negedge clk);
            wvalid = 1'b0;
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
        input logic [7:0] address,
        input logic [31:0] value,
        input integer order,
        output logic [1:0] write_response
    );
        integer aw_done;
        integer w_done;

        begin
            if (order == 1)
            begin
                send_aw(address);
                send_w(value);
            end
            else if (order == 2)
            begin
                send_w(value);
                send_aw(address);
            end
            else
            begin
                aw_done = 0;
                w_done  = 0;

                @(negedge clk);

                awaddr  = address;
                awvalid = 1'b1;

                wdata   = value;
                wstrb   = 4'hf;
                wvalid  = 1'b1;

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
                        aw_done = 1;

                    if (
                        wvalid &&
                        wready
                    )
                        w_done = 1;

                    @(negedge clk);

                    if (aw_done)
                        awvalid = 1'b0;

                    if (w_done)
                        wvalid = 1'b0;
                end
            end

            while (bvalid !== 1'b1)
                @(posedge clk);

            write_response = bresp;

            @(posedge clk);
        end
    endtask

    task automatic axi_read(
        input logic [7:0] address,
        output logic [31:0] value,
        output logic [1:0] read_response
    );
        begin
            @(negedge clk);

            araddr  = address;
            arvalid = 1'b1;

            while (!(arvalid && arready))
                @(posedge clk);

            @(negedge clk);
            arvalid = 1'b0;

            while (rvalid !== 1'b1)
                @(posedge clk);

            value = rdata;
            read_response = rresp;

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

    initial
    begin
        $readmemh(
            "../model/golden/input_a.mem",
            input_a
        );

        $readmemh(
            "../model/golden/input_b.mem",
            input_b
        );

        $readmemh(
            "../model/golden/convolution.mem",
            expected
        );

        repeat (5) @(posedge clk);

        @(negedge clk);
        reset_n = 1'b1;

        /*
         * Confirm fixed identification and profile registers.
         */
        axi_read(
            REG_VERSION,
            read_value,
            response
        );

        require_okay(response, 0);

        if (read_value !== 32'h0001_0000)
        begin
            $display(
                "FAIL VERSION result=%08x expected=00010000",
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

        if (read_value !== 32'd16)
        begin
            $display(
                "FAIL N result=%0d expected=16",
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

        if (read_value !== 32'd112)
        begin
            $display(
                "FAIL MULTS result=%0d expected=112",
                read_value
            );

            $fatal(1);
        end

        $display(
            "PASS: identification registers"
        );

        /*
         * Exercise all three legal AW/W arrival orders while loading.
         */
        for (i = 0; i < 16; i = i + 1)
        begin
            axi_write(
                A_BASE + (i * 4),
                input_a[i],
                i % 3,
                response
            );

            require_okay(
                response,
                10 + i
            );
        end

        for (i = 0; i < 16; i = i + 1)
        begin
            axi_write(
                B_BASE + (i * 4),
                input_b[i],
                (i + 1) % 3,
                response
            );

            require_okay(
                response,
                30 + i
            );
        end

        /*
         * Verify source-window readback.
         */
        axi_read(
            A_BASE,
            read_value,
            response
        );

        require_okay(response, 50);

        if (read_value !== input_a[0])
        begin
            $display(
                "FAIL A readback result=%0d expected=%0d",
                read_value,
                input_a[0]
            );

            $fatal(1);
        end

        axi_read(
            B_BASE + 8'h3c,
            read_value,
            response
        );

        require_okay(response, 51);

        if (read_value !== input_b[15])
        begin
            $display(
                "FAIL B readback result=%0d expected=%0d",
                read_value,
                input_b[15]
            );

            $fatal(1);
        end

        $display(
            "PASS: loaded and read back A and B through AXI-Lite"
        );

        /*
         * Start the complete polynomial multiplication.
         */
        axi_write(
            REG_CONTROL,
            32'd1,
            0,
            response
        );

        require_okay(response, 60);

        /*
         * Wait until busy becomes visible.
         */
        polls = 0;
        read_value = 32'd0;

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
                61
            );

            polls = polls + 1;
        end

        if (!read_value[0])
        begin
            $display(
                "FAIL: busy was never observed"
            );

            $fatal(1);
        end

        /*
         * Source windows are protected while the engine is active.
         */
        axi_write(
            A_BASE,
            32'd123,
            1,
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
            "PASS: writes are rejected while the engine is busy"
        );

        /*
         * Poll sticky completion through the public status register.
         */
        polls = 0;
        read_value = 32'd0;

        while (
            !read_value[1] &&
            polls < 10000
        )
        begin
            axi_read(
                REG_STATUS,
                read_value,
                response
            );

            require_okay(
                response,
                70
            );

            polls = polls + 1;
        end

        if (!read_value[1])
        begin
            $display(
                "FAIL: completion was not observed after %0d polls",
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

        axi_read(
            REG_CYCLES,
            read_value,
            response
        );

        require_okay(response, 71);

        if (read_value == 32'd0)
        begin
            $display(
                "FAIL: cycle count remained zero"
            );

            $fatal(1);
        end

        $display(
            "PASS: AXI status and sticky completion"
        );

        $display(
            "Hardware-reported cycles: %0d",
            read_value
        );

        /*
         * Read and validate all sixteen product coefficients.
         */
        for (i = 0; i < 16; i = i + 1)
        begin
            axi_read(
                RESULT_BASE + (i * 4),
                read_value,
                response
            );

            require_okay(
                response,
                100 + i
            );

            if (read_value !== expected[i])
            begin
                $display(
                    "FAIL RESULT address=%0d result=%0d expected=%0d",
                    i,
                    read_value,
                    expected[i]
                );

                $fatal(1);
            end
        end

        $display(
            "PASS: AXI-Lite result window matches golden convolution"
        );

        /*
         * Clear the sticky completion flag.
         */
        axi_write(
            REG_CONTROL,
            32'd2,
            2,
            response
        );

        require_okay(response, 130);

        axi_read(
            REG_STATUS,
            read_value,
            response
        );

        require_okay(response, 131);

        if (read_value[1])
        begin
            $display(
                "FAIL: sticky completion did not clear"
            );

            $fatal(1);
        end

        /*
         * Verify an unmapped read returns SLVERR.
         */
        axi_read(
            8'he0,
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
            "PASS: complete poly_mul16 AXI-Lite peripheral verified"
        );

        $display(
            "Register span: 0x00-0xDC"
        );

        $finish;
    end

endmodule
