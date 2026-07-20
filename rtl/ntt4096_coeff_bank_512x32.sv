module ntt4096_coeff_bank_512x32 (
    input  logic        clk,

    input  logic        read_en,
    input  logic [8:0]  read_addr,
    output logic [31:0] read_data,

    input  logic        write_en,
    input  logic [8:0]  write_addr,
    input  logic [31:0] write_data
);

    (* ram_style = "block" *)
    logic [31:0] memory [0:511];

    always_ff @(posedge clk)
    begin
        if (write_en)
        begin
            memory[write_addr] <=
                write_data;
        end

        if (read_en)
        begin
            read_data <=
                memory[read_addr];
        end
    end

endmodule
