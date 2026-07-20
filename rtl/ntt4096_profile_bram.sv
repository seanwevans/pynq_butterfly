`timescale 1ns/1ps

/*
 * 4096 x 32-bit runtime-programmable profile memory.
 *
 * The arithmetic core owns the synchronous read port while a product is
 * running. Software owns the independent write port while the core is
 * idle. This maps one N=4096 profile table to four RAMB36 primitives.
 */
module ntt4096_profile_bram (
    input  logic        clk,

    input  logic        read_enable,
    input  logic [11:0] read_address,
    output logic [31:0] read_data,

    input  logic        write_enable,
    input  logic [11:0] write_address,
    input  logic [31:0] write_data
);

    (* ram_style = "block" *)
    logic [31:0] memory [0:4095];

    always_ff @(posedge clk)
    begin
        if (read_enable)
        begin
            read_data <=
                memory[read_address];
        end
    end

    always_ff @(posedge clk)
    begin
        if (write_enable)
        begin
            memory[write_address] <=
                write_data;
        end
    end

`ifndef SYNTHESIS

    always @(posedge clk)
    begin
        if (
            read_enable
            && write_enable
            && read_address == write_address
        )
        begin
            $display(
                "ERROR: runtime profile BRAM read/write collision address=%0d",
                read_address
            );

            $fatal(1);
        end
    end

`endif

endmodule
