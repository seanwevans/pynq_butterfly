`timescale 1ns/1ps

/*
 * 4096 x 32-bit synchronous factor ROM.
 *
 * Used for the forward twist factors psi^j and, later, for inverse
 * scale factors N^-1 psi^-j.
 */
module ntt4096_factor_rom #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        enable,
    input  logic [11:0] address,
    output logic [31:0] read_data
);

    (* rom_style = "block" *)
    logic [31:0] memory [0:4095];

    initial
    begin
`ifndef SYNTHESIS
        if (INIT_FILE == "")
        begin
            $display(
                "ERROR: ntt4096_factor_rom requires INIT_FILE"
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
        if (enable)
        begin
            read_data <=
                memory[address];
        end
    end

endmodule
