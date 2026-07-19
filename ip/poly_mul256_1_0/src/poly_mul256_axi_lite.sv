`timescale 1ns/1ps

/*
 * AXI4-Lite wrapper for the complete N=256 negacyclic polynomial
 * multiplier.
 *
 * Register map:
 *
 *   0x0000 CONTROL
 *          bit 0: start
 *          bit 1: clear sticky completion
 *
 *   0x0004 STATUS
 *          bit 0: busy
 *          bit 1: sticky completion
 *
 *   0x0008 CYCLES
 *   0x000C VERSION
 *   0x0010 MODULUS
 *   0x0014 POLYNOMIAL LENGTH
 *   0x0018 MODULAR MULTIPLICATIONS
 *
 *   0x0100-0x04FC A[0..255], write-only
 *   0x0500-0x08FC B[0..255], write-only
 *   0x0900-0x0CFC RESULT[0..255], read-only
 *
 * AW and W are captured independently.
 *
 * Result reads account for the one-clock latency of the underlying
 * result BRAM.
 */
module poly_mul256_axi_lite #(
    parameter FORWARD_TWIST_INIT_FILE =
        "twist_factors.mem",

    parameter FORWARD_TWIDDLE_INIT_FILE =
        "forward_twiddles.mem",

    parameter INVERSE_TWIDDLE_INIT_FILE =
        "inverse_twiddles.mem",

    parameter INVERSE_SCALE_INIT_FILE =
        "inverse_scale_factors.mem"
) (
    input  wire         S_AXI_ACLK,
    input  wire         S_AXI_ARESETN,

    input  wire [15:0]  S_AXI_AWADDR,
    input  wire [2:0]   S_AXI_AWPROT,
    input  wire         S_AXI_AWVALID,
    output wire         S_AXI_AWREADY,

    input  wire [31:0]  S_AXI_WDATA,
    input  wire [3:0]   S_AXI_WSTRB,
    input  wire         S_AXI_WVALID,
    output wire         S_AXI_WREADY,

    output logic [1:0]  S_AXI_BRESP,
    output logic        S_AXI_BVALID,
    input  wire         S_AXI_BREADY,

    input  wire [15:0]  S_AXI_ARADDR,
    input  wire [2:0]   S_AXI_ARPROT,
    input  wire         S_AXI_ARVALID,
    output wire         S_AXI_ARREADY,

    output logic [31:0] S_AXI_RDATA,
    output logic [1:0]  S_AXI_RRESP,
    output logic        S_AXI_RVALID,
    input  wire         S_AXI_RREADY
);

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

    localparam logic [15:0] A_LAST =
        16'h04fc;

    localparam logic [15:0] B_BASE =
        16'h0500;

    localparam logic [15:0] B_LAST =
        16'h08fc;

    localparam logic [15:0] RESULT_BASE =
        16'h0900;

    localparam logic [15:0] RESULT_LAST =
        16'h0cfc;

    localparam logic [31:0] PROFILE_Q =
        32'd1073692673;

    localparam logic [31:0] VERSION =
        32'h0002_0000;

    /*
     * Independent AXI write-channel holding registers.
     */
    logic        aw_pending;
    logic [15:0] awaddr_hold;

    logic        w_pending;
    logic [31:0] wdata_hold;
    logic [3:0]  wstrb_hold;

    /*
     * AXI read pipeline.
     */
    logic        read_pending;
    logic [15:0] read_address_hold;

    /*
     * Polynomial multiplier interface.
     */
    logic        core_start;

    logic        core_load_we;
    logic        core_load_bank;
    logic [7:0]  core_load_addr;
    logic [31:0] core_load_data;

    logic [7:0]  core_read_addr;
    logic [31:0] core_read_data;

    logic        core_busy;
    logic        core_done;

    logic [31:0] core_cycles;
    logic [12:0] core_multiplication_count;

    logic done_sticky;

    wire engine_busy =
        core_busy ||
        core_start;

    wire current_ar_is_result =
        (S_AXI_ARADDR >= RESULT_BASE) &&
        (S_AXI_ARADDR <= RESULT_LAST) &&
        (S_AXI_ARADDR[1:0] == 2'b00);

    wire held_ar_is_result =
        (read_address_hold >= RESULT_BASE) &&
        (read_address_hold <= RESULT_LAST) &&
        (read_address_hold[1:0] == 2'b00);

    assign S_AXI_AWREADY =
        !aw_pending &&
        !S_AXI_BVALID;

    assign S_AXI_WREADY =
        !w_pending &&
        !S_AXI_BVALID;

    assign S_AXI_ARREADY =
        !read_pending &&
        !S_AXI_RVALID;

    /*
     * On an AR handshake, present the requested result address to the
     * synchronous result BRAM immediately. Hold it during the pending
     * read cycle.
     */
    always @*
    begin
        core_read_addr =
            8'd0;

        if (
            S_AXI_ARVALID &&
            S_AXI_ARREADY &&
            current_ar_is_result
        )
        begin
            core_read_addr =
                (S_AXI_ARADDR - RESULT_BASE) >> 2;
        end
        else if (
            read_pending &&
            held_ar_is_result
        )
        begin
            core_read_addr =
                (read_address_hold - RESULT_BASE) >> 2;
        end
    end

    poly_mul256_core #(
        .FORWARD_TWIST_INIT_FILE(
            FORWARD_TWIST_INIT_FILE
        ),

        .FORWARD_TWIDDLE_INIT_FILE(
            FORWARD_TWIDDLE_INIT_FILE
        ),

        .INVERSE_TWIDDLE_INIT_FILE(
            INVERSE_TWIDDLE_INIT_FILE
        ),

        .INVERSE_SCALE_INIT_FILE(
            INVERSE_SCALE_INIT_FILE
        )
    ) polynomial_multiplier (
        .clk                          (S_AXI_ACLK),
        .reset_n                      (S_AXI_ARESETN),
        .start                        (core_start),

        .load_we                      (core_load_we),
        .load_bank                    (core_load_bank),
        .load_addr                    (core_load_addr),
        .load_data                    (core_load_data),

        .read_addr                    (core_read_addr),
        .read_data                    (core_read_data),

        .busy                         (core_busy),
        .done                         (core_done),

        .cycles                       (core_cycles),

        .modular_multiplication_count (
            core_multiplication_count
        )
    );

    /*
     * AXI writes and core command generation.
     */
    always_ff @(posedge S_AXI_ACLK)
    begin
        if (!S_AXI_ARESETN)
        begin
            aw_pending <=
                1'b0;

            awaddr_hold <=
                16'd0;

            w_pending <=
                1'b0;

            wdata_hold <=
                32'd0;

            wstrb_hold <=
                4'd0;

            S_AXI_BRESP <=
                AXI_OKAY;

            S_AXI_BVALID <=
                1'b0;

            core_start <=
                1'b0;

            core_load_we <=
                1'b0;

            core_load_bank <=
                1'b0;

            core_load_addr <=
                8'd0;

            core_load_data <=
                32'd0;

            done_sticky <=
                1'b0;
        end
        else
        begin
            core_start <=
                1'b0;

            core_load_we <=
                1'b0;

            if (core_done)
            begin
                done_sticky <=
                    1'b1;
            end

            if (
                S_AXI_AWVALID &&
                S_AXI_AWREADY
            )
            begin
                aw_pending <=
                    1'b1;

                awaddr_hold <=
                    S_AXI_AWADDR;
            end

            if (
                S_AXI_WVALID &&
                S_AXI_WREADY
            )
            begin
                w_pending <=
                    1'b1;

                wdata_hold <=
                    S_AXI_WDATA;

                wstrb_hold <=
                    S_AXI_WSTRB;
            end

            if (
                aw_pending &&
                w_pending &&
                !S_AXI_BVALID
            )
            begin
                aw_pending <=
                    1'b0;

                w_pending <=
                    1'b0;

                S_AXI_BRESP <=
                    AXI_OKAY;

                S_AXI_BVALID <=
                    1'b1;

                if (
                    awaddr_hold[1:0]
                    != 2'b00
                )
                begin
                    S_AXI_BRESP <=
                        AXI_SLVERR;
                end
                else if (
                    wstrb_hold != 4'hf
                )
                begin
                    /*
                     * Input memories contain complete 32-bit residues.
                     * Partial-word writes are intentionally rejected.
                     */
                    S_AXI_BRESP <=
                        AXI_SLVERR;
                end
                else if (
                    awaddr_hold == REG_CONTROL
                )
                begin
                    if (wdata_hold[1])
                    begin
                        done_sticky <=
                            1'b0;
                    end

                    if (wdata_hold[0])
                    begin
                        if (engine_busy)
                        begin
                            S_AXI_BRESP <=
                                AXI_SLVERR;
                        end
                        else
                        begin
                            core_start <=
                                1'b1;

                            done_sticky <=
                                1'b0;
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
                        S_AXI_BRESP <=
                            AXI_SLVERR;
                    end
                    else
                    begin
                        core_load_we <=
                            1'b1;

                        core_load_bank <=
                            1'b0;

                        core_load_addr <=
                            (awaddr_hold - A_BASE) >> 2;

                        core_load_data <=
                            wdata_hold;
                    end
                end
                else if (
                    (awaddr_hold >= B_BASE) &&
                    (awaddr_hold <= B_LAST)
                )
                begin
                    if (engine_busy)
                    begin
                        S_AXI_BRESP <=
                            AXI_SLVERR;
                    end
                    else
                    begin
                        core_load_we <=
                            1'b1;

                        core_load_bank <=
                            1'b1;

                        core_load_addr <=
                            (awaddr_hold - B_BASE) >> 2;

                        core_load_data <=
                            wdata_hold;
                    end
                end
                else
                begin
                    S_AXI_BRESP <=
                        AXI_SLVERR;
                end
            end

            if (
                S_AXI_BVALID &&
                S_AXI_BREADY
            )
            begin
                S_AXI_BVALID <=
                    1'b0;
            end
        end
    end

    /*
     * AXI read channel.
     *
     * Every read uses one pending cycle. This naturally accommodates
     * the synchronous result BRAM.
     */
    always_ff @(posedge S_AXI_ACLK)
    begin
        if (!S_AXI_ARESETN)
        begin
            read_pending <=
                1'b0;

            read_address_hold <=
                16'd0;

            S_AXI_RDATA <=
                32'd0;

            S_AXI_RRESP <=
                AXI_OKAY;

            S_AXI_RVALID <=
                1'b0;
        end
        else
        begin
            if (
                S_AXI_ARVALID &&
                S_AXI_ARREADY
            )
            begin
                read_address_hold <=
                    S_AXI_ARADDR;

                read_pending <=
                    1'b1;
            end
            else if (read_pending)
            begin
                read_pending <=
                    1'b0;

                S_AXI_RDATA <=
                    32'd0;

                S_AXI_RRESP <=
                    AXI_OKAY;

                S_AXI_RVALID <=
                    1'b1;

                if (
                    read_address_hold[1:0]
                    != 2'b00
                )
                begin
                    S_AXI_RRESP <=
                        AXI_SLVERR;
                end
                else if (
                    read_address_hold == REG_CONTROL
                )
                begin
                    S_AXI_RDATA <=
                        32'd0;
                end
                else if (
                    read_address_hold == REG_STATUS
                )
                begin
                    S_AXI_RDATA <= {
                        30'd0,
                        done_sticky,
                        engine_busy
                    };
                end
                else if (
                    read_address_hold == REG_CYCLES
                )
                begin
                    S_AXI_RDATA <=
                        core_cycles;
                end
                else if (
                    read_address_hold == REG_VERSION
                )
                begin
                    S_AXI_RDATA <=
                        VERSION;
                end
                else if (
                    read_address_hold == REG_MODULUS
                )
                begin
                    S_AXI_RDATA <=
                        PROFILE_Q;
                end
                else if (
                    read_address_hold == REG_N
                )
                begin
                    S_AXI_RDATA <=
                        32'd256;
                end
                else if (
                    read_address_hold == REG_MULTS
                )
                begin
                    S_AXI_RDATA <=
                        32'd4096;
                end
                else if (
                    (read_address_hold >= RESULT_BASE) &&
                    (read_address_hold <= RESULT_LAST)
                )
                begin
                    if (engine_busy)
                    begin
                        S_AXI_RRESP <=
                            AXI_SLVERR;
                    end
                    else
                    begin
                        S_AXI_RDATA <=
                            core_read_data;
                    end
                end
                else
                begin
                    /*
                     * A and B are intentionally write-only.
                     */
                    S_AXI_RRESP <=
                        AXI_SLVERR;
                end
            end
            else if (
                S_AXI_RVALID &&
                S_AXI_RREADY
            )
            begin
                S_AXI_RVALID <=
                    1'b0;
            end
        end
    end

endmodule
