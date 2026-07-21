`timescale 1ns/1ps

module ntt4096_coeff_bank_1024x64 (
    input  logic        clk,

    input  logic        read_en,
    input  logic [9:0]  read_addr,
    output logic [63:0] read_data,

    input  logic        write_en,
    input  logic [9:0]  write_addr,
    input  logic [63:0] write_data
);

    (* ram_style = "block" *) logic [63:0] memory [0:1023];

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
