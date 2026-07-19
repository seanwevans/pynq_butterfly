`timescale 1ns/1ps

/*
 * 256 x 32-bit true dual-port block RAM.
 *
 * Each port provides:
 *
 *     synchronous one-clock read
 *     optional synchronous write
 *
 * Read-during-write behavior is read-first.
 *
 * The separate clocked process for each port is the standard Vivado
 * true-dual-port block-RAM inference structure. Both ports currently
 * share the same clock, but remain structurally independent.
 */
module ntt256_coeff_bram (
    input  logic        clk,

    input  logic        port_a_enable,
    input  logic        port_a_write_enable,
    input  logic [7:0]  port_a_address,
    input  logic [31:0] port_a_write_data,
    output logic [31:0] port_a_read_data,

    input  logic        port_b_enable,
    input  logic        port_b_write_enable,
    input  logic [7:0]  port_b_address,
    input  logic [31:0] port_b_write_data,
    output logic [31:0] port_b_read_data
);

    import ntt256_profile_pkg::*;

    (* ram_style = "block" *)
    logic [31:0] memory [0:NTT_N-1];

    /*
     * Port A.
     */
    always @(posedge clk)
    begin
        if (port_a_enable)
        begin
            port_a_read_data <=
                memory[port_a_address];

            if (port_a_write_enable)
            begin
                memory[port_a_address] <=
                    port_a_write_data;
            end
        end
    end

    /*
     * Port B.
     *
     * Vivado's true-dual-port inference requires this to be a
     * separate clocked process rather than combining both ports into
     * one process.
     */
    always @(posedge clk)
    begin
        if (port_b_enable)
        begin
            port_b_read_data <=
                memory[port_b_address];

            if (port_b_write_enable)
            begin
                memory[port_b_address] <=
                    port_b_write_data;
            end
        end
    end

`ifndef SYNTHESIS

    /*
     * Same-address access is safe when both ports only read. Any
     * same-address transaction involving a write is forbidden because
     * primitive collision behavior is device- and mode-dependent.
     */
    always @(posedge clk)
    begin
        if (
            port_a_enable &&
            port_b_enable &&
            (port_a_address == port_b_address) &&
            (
                port_a_write_enable ||
                port_b_write_enable
            )
        )
        begin
            $display(
                "ERROR: forbidden coefficient-BRAM collision address=%0d",
                port_a_address
            );

            $fatal(1);
        end
    end

`endif

endmodule
