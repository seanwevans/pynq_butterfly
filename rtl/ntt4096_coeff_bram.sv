`timescale 1ns/1ps

/*
 * 4096 x 32-bit true dual-port coefficient block RAM.
 *
 * Both ports have:
 *
 *     synchronous one-clock read
 *     optional synchronous write
 *     read-first behavior during a same-port write
 *
 * The ports share one clock but use separate clocked processes so
 * Vivado can infer a true dual-port block RAM.
 */
module ntt4096_coeff_bram (
    input  logic        clk,

    input  logic        port_a_enable,
    input  logic        port_a_write_enable,
    input  logic [11:0] port_a_address,
    input  logic [31:0] port_a_write_data,
    output logic [31:0] port_a_read_data,

    input  logic        port_b_enable,
    input  logic        port_b_write_enable,
    input  logic [11:0] port_b_address,
    input  logic [31:0] port_b_write_data,
    output logic [31:0] port_b_read_data
);

    import ntt4096_profile_pkg::*;

    (* ram_style = "block" *)
    logic [31:0] memory [0:NTT_N-1];

    always_ff @(posedge clk)
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

    always_ff @(posedge clk)
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
     * Simultaneous reads from one address are valid. Any same-address
     * transaction involving a write is forbidden because primitive
     * collision behavior is mode-dependent.
     */
    always @(posedge clk)
    begin
        if (
            port_a_enable
            && port_b_enable
            && port_a_address == port_b_address
            && (
                port_a_write_enable
                || port_b_write_enable
            )
        )
        begin
            $display(
                "ERROR: forbidden N=4096 coefficient-BRAM collision address=%0d",
                port_a_address
            );

            $fatal(1);
        end
    end

`endif

endmodule
