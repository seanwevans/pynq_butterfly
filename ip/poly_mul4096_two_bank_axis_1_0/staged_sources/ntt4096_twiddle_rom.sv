`timescale 1ns/1ps

/*
 * 4095 x 32-bit synchronous compact twiddle ROM.
 *
 * One instance is used for forward twiddles and another for inverse
 * twiddles.
 */
module ntt4096_twiddle_rom #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        enable,
    input  logic [11:0] address,
    output logic [31:0] read_data
);

    import ntt4096_profile_pkg::*;

    (* rom_style = "block" *)
    logic [31:0] memory [0:NTT_COMPACT_TWIDDLE_WORDS-1];

    initial
    begin
`ifndef SYNTHESIS
        if (INIT_FILE == "")
        begin
            $display(
                "ERROR: ntt4096_twiddle_rom requires INIT_FILE"
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

`ifndef SYNTHESIS

    always_ff @(posedge clk)
    begin
        if (
            enable
            && address >= NTT_COMPACT_TWIDDLE_WORDS
        )
        begin
            $display(
                "ERROR: N=4096 twiddle ROM address out of range: %0d",
                address
            );

            $fatal(1);
        end
    end

`endif

endmodule
