`timescale 1ns/1ps

/*
 * Compact synchronous twiddle ROM.
 *
 * There are N-1 = 255 words:
 *
 *     stage 0:   1 word
 *     stage 1:   2 words
 *     stage 2:   4 words
 *     ...
 *     stage 7: 128 words
 *
 * Vivado should infer a block ROM from this structure.
 */
module ntt256_twiddle_rom #(
    parameter INIT_FILE = ""
) (
    input  logic        clk,
    input  logic [7:0]  address,
    output logic [31:0] data
);

    import ntt256_profile_pkg::*;

    (* rom_style = "block" *)
    logic [31:0] memory [
        0:NTT_TWIDDLE_WORDS-1
    ];

    initial
    begin
`ifndef SYNTHESIS
        if (INIT_FILE == "")
        begin
            $display(
                "ERROR: ntt256_twiddle_rom requires INIT_FILE"
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
