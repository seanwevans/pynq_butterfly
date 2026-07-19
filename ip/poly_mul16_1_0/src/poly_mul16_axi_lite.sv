`timescale 1ns/1ps

/*
 * AXI4-Lite wrapper for poly_mul16_core.
 *
 * Register map:
 *
 *   0x00 CONTROL
 *        bit 0: start
 *        bit 1: clear sticky done
 *
 *   0x04 STATUS
 *        bit 0: busy
 *        bit 1: sticky done
 *
 *   0x08 CYCLES
 *   0x0C VERSION
 *   0x10 MODULUS
 *   0x14 POLYNOMIAL LENGTH
 *   0x18 MODULAR MULTIPLICATIONS PER PRODUCT
 *
 *   0x20-0x5C A[0..15]
 *   0x60-0x9C B[0..15]
 *   0xA0-0xDC RESULT[0..15]
 *
 * The AW and W channels are captured independently. This avoids the
 * deadlock caused by assuming that address and data arrive together.
 */
module poly_mul16_axi_lite (
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,

    input  wire [7:0]  S_AXI_AWADDR,
    input  wire [2:0]  S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,

    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,

    output logic [1:0]  S_AXI_BRESP,
    output logic        S_AXI_BVALID,
    input  wire         S_AXI_BREADY,

    input  wire [7:0]   S_AXI_ARADDR,
    input  wire [2:0]   S_AXI_ARPROT,
    input  wire         S_AXI_ARVALID,
    output wire         S_AXI_ARREADY,

    output logic [31:0] S_AXI_RDATA,
    output logic [1:0]  S_AXI_RRESP,
    output logic        S_AXI_RVALID,
    input  wire         S_AXI_RREADY
);

    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;

    localparam logic [7:0] REG_CONTROL = 8'h00;
    localparam logic [7:0] REG_STATUS  = 8'h04;
    localparam logic [7:0] REG_CYCLES  = 8'h08;
    localparam logic [7:0] REG_VERSION = 8'h0c;
    localparam logic [7:0] REG_MODULUS = 8'h10;
    localparam logic [7:0] REG_N       = 8'h14;
    localparam logic [7:0] REG_MULTS   = 8'h18;

    localparam logic [7:0] A_BASE      = 8'h20;
    localparam logic [7:0] A_LAST      = 8'h5c;

    localparam logic [7:0] B_BASE      = 8'h60;
    localparam logic [7:0] B_LAST      = 8'h9c;

    localparam logic [7:0] RESULT_BASE = 8'ha0;
    localparam logic [7:0] RESULT_LAST = 8'hdc;

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    localparam logic [31:0] VERSION =
        32'h0001_0000;

    /*
     * Independent AXI write-channel holding registers.
     */
    logic       aw_pending;
    logic [7:0] awaddr_hold;

    logic       w_pending;
    logic [31:0] wdata_hold;
    logic [3:0]  wstrb_hold;

    /*
     * Readback shadows for the two source-polynomial windows.
     */
    logic [31:0] a_shadow [0:15];
    logic [31:0] b_shadow [0:15];

    /*
     * Wrapped polynomial multiplier.
     */
    logic        core_start;

    logic        core_load_we;
    logic        core_load_bank;
    logic [3:0]  core_load_addr;
    logic [31:0] core_load_data;

    logic [3:0]  core_read_addr;
    logic [31:0] core_read_data;

    logic core_busy;
    logic core_done;

    logic done_sticky;
    logic cycle_counting;
    logic [31:0] cycle_count;

    wire engine_busy =
        core_busy ||
        core_start ||
        cycle_counting;

    /*
     * Read-data decode.
     */
    logic [31:0] read_data_mux;
    logic [1:0]  read_resp_mux;

    integer reset_index;

    function automatic logic [31:0] merge_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strobes
    );
        logic [31:0] merged;
        begin
            merged = old_value;

            if (strobes[0])
                merged[7:0] = new_value[7:0];

            if (strobes[1])
                merged[15:8] = new_value[15:8];

            if (strobes[2])
                merged[23:16] = new_value[23:16];

            if (strobes[3])
                merged[31:24] = new_value[31:24];

            merge_wstrb = merged;
        end
    endfunction

    assign S_AXI_AWREADY =
        !aw_pending &&
        !S_AXI_BVALID;

    assign S_AXI_WREADY =
        !w_pending &&
        !S_AXI_BVALID;

    assign S_AXI_ARREADY =
        !S_AXI_RVALID;

    /*
     * The result memory has an asynchronous read interface.
     * Drive its address directly from the current AXI read address.
     */
    always @*
    begin
        core_read_addr = 4'd0;

        read_data_mux = 32'd0;
        read_resp_mux = AXI_OKAY;

        if (S_AXI_ARADDR[1:0] != 2'b00)
        begin
            read_resp_mux = AXI_SLVERR;
        end
        else if (S_AXI_ARADDR == REG_CONTROL)
        begin
            read_data_mux = 32'd0;
        end
        else if (S_AXI_ARADDR == REG_STATUS)
        begin
            read_data_mux = {
                30'd0,
                done_sticky,
                engine_busy
            };
        end
        else if (S_AXI_ARADDR == REG_CYCLES)
        begin
            read_data_mux = cycle_count;
        end
        else if (S_AXI_ARADDR == REG_VERSION)
        begin
            read_data_mux = VERSION;
        end
        else if (S_AXI_ARADDR == REG_MODULUS)
        begin
            read_data_mux = PROFILE_Q;
        end
        else if (S_AXI_ARADDR == REG_N)
        begin
            read_data_mux = 32'd16;
        end
        else if (S_AXI_ARADDR == REG_MULTS)
        begin
            read_data_mux = 32'd112;
        end
        else if (
            (S_AXI_ARADDR >= A_BASE) &&
            (S_AXI_ARADDR <= A_LAST)
        )
        begin
            read_data_mux =
                a_shadow[
                    (S_AXI_ARADDR - A_BASE) >> 2
                ];
        end
        else if (
            (S_AXI_ARADDR >= B_BASE) &&
            (S_AXI_ARADDR <= B_LAST)
        )
        begin
            read_data_mux =
                b_shadow[
                    (S_AXI_ARADDR - B_BASE) >> 2
                ];
        end
        else if (
            (S_AXI_ARADDR >= RESULT_BASE) &&
            (S_AXI_ARADDR <= RESULT_LAST)
        )
        begin
            core_read_addr =
                (S_AXI_ARADDR - RESULT_BASE) >> 2;

            read_data_mux =
                core_read_data;
        end
        else
        begin
            read_resp_mux = AXI_SLVERR;
        end
    end

    poly_mul16_core polynomial_multiplier (
        .clk       (S_AXI_ACLK),
        .reset_n   (S_AXI_ARESETN),
        .start     (core_start),

        .load_we   (core_load_we),
        .load_bank (core_load_bank),
        .load_addr (core_load_addr),
        .load_data (core_load_data),

        .read_addr (core_read_addr),
        .read_data (core_read_data),

        .busy      (core_busy),
        .done      (core_done)
    );

    /*
     * AXI write handling, command generation, and performance state.
     */
    always_ff @(posedge S_AXI_ACLK)
    begin
        if (!S_AXI_ARESETN)
        begin
            aw_pending <= 1'b0;
            awaddr_hold <= 8'd0;

            w_pending <= 1'b0;
            wdata_hold <= 32'd0;
            wstrb_hold <= 4'd0;

            S_AXI_BRESP  <= AXI_OKAY;
            S_AXI_BVALID <= 1'b0;

            core_start     <= 1'b0;
            core_load_we   <= 1'b0;
            core_load_bank <= 1'b0;
            core_load_addr <= 4'd0;
            core_load_data <= 32'd0;

            done_sticky   <= 1'b0;
            cycle_counting <= 1'b0;
            cycle_count    <= 32'd0;

            for (
                reset_index = 0;
                reset_index < 16;
                reset_index = reset_index + 1
            )
            begin
                a_shadow[reset_index] <= 32'd0;
                b_shadow[reset_index] <= 32'd0;
            end
        end
        else
        begin
            /*
             * Command outputs are one-clock pulses.
             */
            core_start   <= 1'b0;
            core_load_we <= 1'b0;

            /*
             * Count clocks from the edge at which the core accepts
             * start until the completion pulse is observed.
             */
            if (core_start)
            begin
                cycle_count     <= 32'd0;
                cycle_counting  <= 1'b1;
                done_sticky     <= 1'b0;
            end
            else if (cycle_counting)
            begin
                cycle_count <= cycle_count + 1'b1;

                if (core_done)
                begin
                    cycle_counting <= 1'b0;
                    done_sticky    <= 1'b1;
                end
            end
            else if (core_done)
            begin
                done_sticky <= 1'b1;
            end

            /*
             * Capture AW and W independently.
             */
            if (
                S_AXI_AWVALID &&
                S_AXI_AWREADY
            )
            begin
                aw_pending <= 1'b1;
                awaddr_hold <= S_AXI_AWADDR;
            end

            if (
                S_AXI_WVALID &&
                S_AXI_WREADY
            )
            begin
                w_pending <= 1'b1;
                wdata_hold <= S_AXI_WDATA;
                wstrb_hold <= S_AXI_WSTRB;
            end

            /*
             * Execute one write once both channel payloads exist.
             */
            if (
                aw_pending &&
                w_pending &&
                !S_AXI_BVALID
            )
            begin
                aw_pending <= 1'b0;
                w_pending  <= 1'b0;

                S_AXI_BRESP  <= AXI_OKAY;
                S_AXI_BVALID <= 1'b1;

                if (awaddr_hold[1:0] != 2'b00)
                begin
                    S_AXI_BRESP <= AXI_SLVERR;
                end
                else if (awaddr_hold == REG_CONTROL)
                begin
                    /*
                     * bit 1 clears sticky completion.
                     */
                    if (
                        wstrb_hold[0] &&
                        wdata_hold[1]
                    )
                    begin
                        done_sticky <= 1'b0;
                    end

                    /*
                     * bit 0 launches a new operation.
                     */
                    if (
                        wstrb_hold[0] &&
                        wdata_hold[0]
                    )
                    begin
                        if (engine_busy)
                        begin
                            S_AXI_BRESP <= AXI_SLVERR;
                        end
                        else
                        begin
                            core_start <= 1'b1;
                            done_sticky <= 1'b0;
                        end
                    end
                end
                else if (
                    (awaddr_hold >= A_BASE) &&
                    (awaddr_hold <= A_LAST)
                )
                begin
                    if (engine_busy)
                    begin
                        S_AXI_BRESP <= AXI_SLVERR;
                    end
                    else
                    begin
                        a_shadow[
                            (awaddr_hold - A_BASE) >> 2
                        ] <= merge_wstrb(
                            a_shadow[
                                (awaddr_hold - A_BASE) >> 2
                            ],
                            wdata_hold,
                            wstrb_hold
                        );

                        core_load_we   <= 1'b1;
                        core_load_bank <= 1'b0;

                        core_load_addr <=
                            (awaddr_hold - A_BASE) >> 2;

                        core_load_data <= merge_wstrb(
                            a_shadow[
                                (awaddr_hold - A_BASE) >> 2
                            ],
                            wdata_hold,
                            wstrb_hold
                        );
                    end
                end
                else if (
                    (awaddr_hold >= B_BASE) &&
                    (awaddr_hold <= B_LAST)
                )
                begin
                    if (engine_busy)
                    begin
                        S_AXI_BRESP <= AXI_SLVERR;
                    end
                    else
                    begin
                        b_shadow[
                            (awaddr_hold - B_BASE) >> 2
                        ] <= merge_wstrb(
                            b_shadow[
                                (awaddr_hold - B_BASE) >> 2
                            ],
                            wdata_hold,
                            wstrb_hold
                        );

                        core_load_we   <= 1'b1;
                        core_load_bank <= 1'b1;

                        core_load_addr <=
                            (awaddr_hold - B_BASE) >> 2;

                        core_load_data <= merge_wstrb(
                            b_shadow[
                                (awaddr_hold - B_BASE) >> 2
                            ],
                            wdata_hold,
                            wstrb_hold
                        );
                    end
                end
                else
                begin
                    /*
                     * Status, result, and unknown addresses are
                     * read-only or unmapped.
                     */
                    S_AXI_BRESP <= AXI_SLVERR;
                end
            end

            if (
                S_AXI_BVALID &&
                S_AXI_BREADY
            )
            begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    /*
     * AXI read channel.
     */
    always_ff @(posedge S_AXI_ACLK)
    begin
        if (!S_AXI_ARESETN)
        begin
            S_AXI_RDATA  <= 32'd0;
            S_AXI_RRESP  <= AXI_OKAY;
            S_AXI_RVALID <= 1'b0;
        end
        else
        begin
            if (
                S_AXI_ARVALID &&
                S_AXI_ARREADY
            )
            begin
                S_AXI_RDATA  <= read_data_mux;
                S_AXI_RRESP  <= read_resp_mux;
                S_AXI_RVALID <= 1'b1;
            end
            else if (
                S_AXI_RVALID &&
                S_AXI_RREADY
            )
            begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

endmodule
