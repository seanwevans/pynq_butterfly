`timescale 1ns/1ps

/*
 * Canonical Xilinx simple-dual-port block RAM inference template.
 *
 * Port A: synchronous read.
 * Port B: synchronous write.
 *
 * 1024 x 32 bits maps to one RAMB36E1 on XC7Z020.
 */
module ntt4096_coeff_bank_1024x32 (
    input  logic        clk,

    input  logic        read_en,
    input  logic [9:0]  read_addr,
    output logic [31:0] read_data,

    input  logic        write_en,
    input  logic [9:0]  write_addr,
    input  logic [31:0] write_data
);

    (* ram_style = "block" *)
    logic [31:0] memory [0:1023];

    always_ff @(posedge clk)
    begin
        if (read_en)
        begin
            read_data <=
                memory[read_addr];
        end

        if (write_en)
        begin
            memory[write_addr] <=
                write_data;
        end
    end

endmodule
