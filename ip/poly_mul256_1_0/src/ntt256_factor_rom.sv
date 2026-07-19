`timescale 1ns/1ps

/*
 * Synchronous 256 x 32-bit factor ROM.
 *
 * Used for:
 *
 *     forward: psi^j
 *     inverse: N^-1 * psi^-j
 */
module ntt256_factor_rom #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic [7:0]  address,
    output logic [31:0] data
);

    (* rom_style = "block" *)
    logic [31:0] memory [0:255];

    initial
    begin
`ifndef SYNTHESIS
        if (INIT_FILE == "")
        begin
            $display(
                "ERROR: ntt256_factor_rom requires INIT_FILE"
            );

            $fatal(1);
        end
`endif

        $readmemh(
            INIT_FILE,
            memory
        );
    end

    always_ff @(posedge clk)
    begin
        data <= memory[address];
    end

endmodule
